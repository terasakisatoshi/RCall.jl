"""
A pure julia wrapper of R_tryEval.
"""
function tryEval{S<:Sxp}(expr::Ptr{S}, env::Ptr{EnvSxp})
    status = Array(Cint,1)
    protect(expr)
    protect(env)
    val = ccall((:R_tryEval,libR),UnknownSxpPtr,(Ptr{S},Ptr{EnvSxp},Ptr{Cint}),expr,env,status)
    unprotect(2)
    return val, status[1]
end

"""
Evaluate an R symbol or language object (i.e. a function call) in an R
try/catch block, returning a Sxp pointer.
"""
function reval_p{S<:Sxp}(expr::Ptr{S}, env::Ptr{EnvSxp})
    val, status = tryEval(expr, env)
    flush_printBuffer(STDOUT)
    if status !=0
        error("RCall.jl ", takebuf_string(errorBuffer))
    elseif nb_available(errorBuffer) != 0
        warn("RCall.jl ", takebuf_string(errorBuffer))
    end
    sexp(val)
end

"""
Evaluate an R expression array iteratively.
"""
function reval_p(expr::Ptr{ExprSxp}, env::Ptr{EnvSxp})
    local val           # the value of the last expression is returned
    protect(expr)
    try
        for e in expr
            val = reval_p(e,env)
        end
    finally
        unprotect(1)
    end
    val
end

reval_p{S<:Sxp}(expr::Ptr{S}, env::RObject{EnvSxp}) = reval_p(expr,sexp(env))
reval_p{S<:Sxp}(s::Ptr{S}) = reval_p(s,Const.GlobalEnv)

"""
Evaluate an R symbol or language object (i.e. a function call) in an R
try/catch block, returning an RObject.
"""
reval(s, env=Const.GlobalEnv) = RObject(reval_p(sexp(s),sexp(env)))
reval(str::AbstractString, env=Const.GlobalEnv) = reval(rparse_p(str),env)
reval(sym::Symbol, env=Const.GlobalEnv) = reval(sexp(sym),env)


"""
Evaluate and convert the result of a string as an R expression.
"""
rcopy(str::AbstractString) = rcopy(reval_p(rparse_p(str)))
rcopy(sym::Symbol) = rcopy(reval_p(sexp(sym)))
rcopy{T}(::Type{T}, str::AbstractString) = rcopy(T, reval_p(rparse_p(str)))
rcopy{T}(::Type{T}, sym::Symbol) = rcopy(T, reval_p(sexp(sym)))


"A pure julia wrapper of R_ParseVector"
function ParseVector{S<:Sxp}(st::Ptr{StrSxp}, sf::Ptr{S}=sexp(Const.NilValue))
    protect(st)
    status = Array(Cint,1)
    val = ccall((:R_ParseVector,libR),UnknownSxpPtr,
                (Ptr{StrSxp},Cint,Ptr{Cint},UnknownSxpPtr),
                st,-1,status,sf)
    unprotect(1)
    s = status[1]
    msg = s == 1 ? "" : Compat.unsafe_string(cglobal((:R_ParseErrorMsg, libR), UInt8))
    val, s, msg
end

"Parse a string as an R expression, returning a Sxp pointer."
function rparse_p(st::Ptr{StrSxp})
    val, status, msg = ParseVector(st)
    if status == 2 || status == 3
        error(msg)
    elseif status == 4
        throw(EOFError())
    end
    sexp(val)
end
rparse_p(st::AbstractString) = rparse_p(sexp(st))

"Parse a string as an R expression, returning an RObject."
rparse(st::AbstractString) = RObject(rparse_p(st))


"Print the value of an Sxp using R's printing mechanism"
function rprint{S<:Sxp}(io::IO, s::Ptr{S})
    global PrintBufferLocked
    PrintBufferLocked = true
    protect(s)
    # Rf_PrintValue can cause segfault if S3 objects has custom
    # print function as it doesn't use R_tryEval
    # ccall((:Rf_PrintValue,libR),Void,(Ptr{S},),s)
    # below mirrors Rf_PrintValue
    env = protect(newEnvironment(Const.GlobalEnv))
    env[:x] = s
    if isObject(s) || isFunction(s)
        if isS4(s)
            methodsNamespace = protect(findNamespace("methods"))
            tryEval(rlang_p(methodsNamespace[:show], :x), env)
            unprotect(1)
        else
            tryEval(rlang_p(Const.BaseNamespace[:print], :x) ,env)
        end
    else
        # Rf_PrintValueRec not found on unix!?
        # ccall((:Rf_PrintValueRec,libR),Void,(Ptr{S},Ptr{EnvSxp}),s, Const.GlobalEnv)
        tryEval(rlang_p(Const.BaseNamespace[Symbol("print.default")], :x), env)
    end
    env[:x] = Const.NilValue
    write(io,takebuf_string(printBuffer))

    # in general, only S3/S4 custom print will fail
    if nb_available(errorBuffer) != 0
        warn(takebuf_string(errorBuffer))
    end
    unprotect(2)
    PrintBufferLocked = false
    nothing
end
rprint(io::IO,r::RObject) = rprint(io,r.p)

rprint(s) = rprint(STDOUT,s)



"""
Parse, evaluate and print the result of a string as an R expression.
"""
rprint(io::IO,str::Compat.String) = rprint(io,reval(str))
rprint(io::IO,sym::Symbol) = rprint(io,reval(sym))

"""
Copies variables from Julia to R using the same name.
"""
macro rput(args...)
    blk = Expr(:block)
    for a in args
        if isa(a,Symbol)
            v = a
            push!(blk.args,:(Const.GlobalEnv[$(QuoteNode(v))] = $(esc(v))))
        elseif isa(a,Expr) && a.head == :(::)
            v = a.args[1]
            S = a.args[2]
            push!(blk.args,:(Const.GlobalEnv[$(QuoteNode(v))] = sexp($S,$(esc(v)))))
        else
            error("Incorrect usage of @rput")
        end
    end
    blk
end

"""
Copies variables from R to Julia using the same name.
"""
macro rget(args...)
    blk = Expr(:block)
    for a in args
        if isa(a,Symbol)
            v = a
            push!(blk.args,:($(esc(v)) = rcopy(Const.GlobalEnv[$(QuoteNode(v))])))
        elseif isa(a,Expr) && a.head == :(::)
            v = a.args[1]
            T = a.args[2]
            push!(blk.args,:($(esc(v)) = rcopy($(esc(T)),Const.GlobalEnv[$(QuoteNode(v))])))
        else
            error("Incorrect usage of @rget")
        end
    end
    blk
end