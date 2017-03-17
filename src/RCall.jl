__precompile__()
module RCall
using Compat

import DataFrames: DataFrame, AbstractDataFrame, Formula
import DataArrays
import DataArrays: DataArray, PooledDataArray, AbstractDataArray, RefArray

import NullableArrays: NullableArray
import CategoricalArrays
import CategoricalArrays: CategoricalArray, CategoricalPool, NullableCategoricalArray

import AxisArrays
import AxisArrays: AxisArray, Axis

import DataStructures: OrderedDict

import Base: eltype, show, convert, isascii, isnull,
    length, size, getindex, setindex!, start, next, done, names

export RObject,
   Sxp, NilSxp, StrSxp, CharSxp, LglSxp, IntSxp, RealSxp, CplxSxp,
   ListSxp, VecSxp, EnvSxp, LangSxp, ClosSxp, S4Sxp,
   getattrib, setattrib!, getnames, setnames!, getclass, setclass!, attributes,
   globalEnv,
   isna, anyna,
   rcopy, rparse, rprint, reval, rcall, rlang,
   @rimport, @rlibrary, @rput, @rget, @var_str, @R_str


include("setup.jl")
include("types.jl")
include("constants.jl")
include("methods.jl")
include("convert/base.jl")
include("convert/dataframe.jl")
include("convert/datatable.jl")
include("convert/axisarray.jl")
include("convert/default.jl")
include("eventloop.jl")
include("eval.jl")
include("io.jl")
include("functions.jl")
include("callback.jl")
include("operators.jl")
include("library.jl")
include("IJulia.jl")
include("render.jl")
include("macros.jl")
include("repl.jl")
include("deprecated.jl")

end # module
