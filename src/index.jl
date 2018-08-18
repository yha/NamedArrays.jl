# index.jl getindex and setindex methods for NamedArray
## (c) 2013--2018 David A. van Leeuwen

## This code is licensed under the MIT license
## See the file LICENSE.md in this distribution

import Base: getindex, setindex!

## AbstractArray Interface, integers have precedence over everything else
getindex(n::NamedArray{T, N, AT, DT}, i::Int) where {T, N, AT, DT} = getindex(n.array, i)
getindex(n::NamedArray{T, N, AT, DT}, I::Vararg{Int, N}) where {T, N, AT, DT} = getindex(n.array, I...)
setindex!(n::NamedArray{T, N, AT, DT}, v, i::Int) where {T, N, AT, DT} = setindex!(n.array, v, i::Int)
setindex!(n::NamedArray{T, N, AT, DT}, v, I::Vararg{Int, N}) where {T, N, AT, DT} = setindex!(n.array, v, I...)
## optional methods
Base.IndexStyle(n::NamedArray) = IndexStyle(n.array)

## Ambiguity
#getindex(n::NamedArray{T, 1, AT, DT}, i::Int64) where {T, AT, DT} = getindex(n.array, i)
#setindex!(n::NamedArray{T, 1, AT, DT}, v::Any, i::Int64) where {T, AT, DT} = setindex!(n.array, v, i)

function flattenednames(n::NamedArray)
    L = length(n) # elements in array
    cols = Array[]
    factor = 1
    for d in 1:ndims(n)
        nlevels = size(n, d)
        nrep = L ÷ (nlevels * factor)
        data = repeat(vcat([fill(x, factor) for x in names(n, d)]...), nrep)
        push!(cols, data)
        factor *= nlevels
    end
    return collect(zip(cols...))
end

## from subarray.jl
getindex(n::NamedVector, ::Colon) = n
getindex(n::NamedArray, ::Colon) = NamedArray(n.array[:], [flattenednames(n)] , [tuple(dimnames(n)...)])

## special 0-dimensional case
## getindex{T}(n::NamedArray{T,0}, i::Real) = getindex(n.array, i)

getindex(n::NamedArray{T, N, AT, DT}, I::Vararg{Any,N}) where {T, N, AT, DT} = namedgetindex(n, map((d,i)->indices(d, i), n.dicts, I)...)

Base.view(n::NamedArray{T,N}, I::Vararg{Union{AbstractArray,Colon,Real},N}) where {T,N} = namedgetindex(n, map((d,i)->indices(d, i), n.dicts, I)...; useview=true)
Base.view(n::NamedArray{T,N}, I::Vararg{Any,N}) where {T,N} = namedgetindex(n, map((d,i)->indices(d, i), n.dicts, I)...; useview=true)

## indices computes numeric indices from named or other

## indices(::Associative, index) converts any type `index` to Integer

## single index
indices(dict::AbstractDict{K,V}, i::Integer) where {K, V<:Integer} = i ## integer index takes precedence
## indices(dict::Associative{K,V}, i::K) where {K<:Real, V<:Integer} = dict[i]
## indices(dict::Associative{K,V}, i::Real) where {K, V<:Integer} = Base.to_index(i)
indices(dict::AbstractDict{K,V}, i::K) where {K, V<:Integer} = dict[i]
indices(dict::AbstractDict{K,V}, i::Name{K}) where {K, V<:Integer} = dict[i.name]


## ambiguity if dict key is CartesionIndex, this should never happen
# indices(dict::AbstractDict{K,V}, i::K) where {K<:CartesianIndex,V<:Integer} = dict[i]
indices(dict::AbstractDict, ci::CartesianIndex) = ci
indices(dict::AbstractDict{Any,V}, ci::CartesianIndex) where {V<:Integer} = ci

## multiple indices
## the following two lines are partly because of ambiguity
#indices(dict::Associative{T,V}, i::AbstractArray{T}) where {T<:Integer,V<:Integer} = [dict[k] for k in i]
#indices(dict::Associative{T,V}, i::AbstractArray{T}) where {T<:Real,V<:Integer} = [dict[k] for k in i]

indices(dict::AbstractDict{K,V}, i::AbstractArray) where {K,V<:Integer} = [indices(dict, k) for k in i]
#indices(dict::Associative{K,V}, i::AbstractArray{T}) where {T<:Integer,K,V<:Integer} = i
#indices(dict::Associative{K,V}, i::AbstractArray{K}) where {K,V<:Integer} = [dict[k] for k in i]
#indices(dict::Associative{K,V}, i::AbstractArray{Name{K}}) where {K, V<:Integer} = [dict[k.name] for k in i]
## in 0.4, we need to take care of : ourselves it seems
indices(dict::AbstractDict{K,V}, ::Colon) where {K,V<:Integer} = collect(1:length(dict))

## negation
indices(dict::AbstractDict{K,V}, i::K) where {K<:Not,V<:Integer} = dict[i]
indices(dict::AbstractDict, i::Not) = setdiff(1:length(dict), indices(dict, i.index))

## namedgetindex collects the elements from the array, and takes care of the index names
## `index` is an integer now, or an array of integers, or a cartesianindex
## and has been computed by `indices()`

## Simple scalar indexing
@inline namedgetindex(n::NamedArray, I::Vararg{Integer,N}) where {N} = getindex(n.array, I...)

dimkeepingtype(x) = false
dimkeepingtype(x::AbstractArray) = true
dimkeepingtype(x::AbstractRange) = true
dimkeepingtype(x::BitArray) = true

## Slices etc.
namedgetindex(n::NamedArray, index::CartesianIndex) = getindex(n.array, index)
function namedgetindex(n::NamedArray, index...; useview=false)
    if useview
        a = view(n.array, index...)
    else
        a = getindex(n.array, index...)
    end
    if !isa(a, AbstractArray)
        return(a)
    end
    N = length(index)
    keeping = filter(i -> dimkeepingtype(index[i]), 1:N)
    if ndims(a) < length(keeping) ## || length(dims) == 1 && ndims(n) > 1
        warn("Dropped names for ", typeof(n.array), " with index ", index)
        return a;               # number of dimension changed, this should not happen
    end
    newnames = Any[]
    newdimnames = []
    for d in keeping
        if ndims(index[d]) > 1
            ## take over the names of the index for this dimension
            for (name, dimname) in zip(defaultnames(index[d]), dimnames(index[d]))
                push!(newnames, name)
                push!(newdimnames, Symbol(string(n.dimnames[d], "_", dimname)))
            end
        else
            push!(newnames, names(n, d)[index[d]])
            push!(newdimnames, n.dimnames[d])
        end
    end
    return NamedArray(a, tuple(newnames...), tuple(newdimnames...))
end

## work out n[:A => "1", :C => "5"]
function indices(n::NamedArray, I::Pair...)
    dict = Dict{Any,Any}(I...)
    Set(keys(dict)) ⊆ Set(n.dimnames) || error("Dimension name mismatch")
    result = Vector{Union{Int,Colon}}(undef, ndims(n))
    fill!(result, :) ## unspecified dimensions act as colon
    for (i, dim) in enumerate(n.dimnames)
        if dim in keys(dict)
            result[i] = n.dicts[i][dict[dim]]
        end
    end
    return result
end

getindex(n::NamedArray, I::Pair...) = getindex(n.array, indices(n, I...)...)
## 0.6 ambiguity
getindex(n::NamedVector, I::CartesianIndex{1}) = getindex(n.array, I)
getindex(n::NamedArray{T,N}, I::CartesianIndex{N}) where {T,N} = getindex(n.array, I)

## Setindex is remarkably more simple than getindex.  I wonder why...

## This takes care of most cases
@inline function setindex!(n::NamedArray{T,N}, x, I::Vararg{Any,N}) where {T,N}
    II = map((d,i)->indices(d, i), n.dicts, I)
    n.array[II...] = x
end

## assignment via n[:B => "two"] = [...]
@inline setindex!(n::NamedArray, x, I::Vararg{Pair}) = setindex!(n.array, x, indices(n, I...)...)

# _name2index(dict::OrderedDict{K,Int}, value::Any) where K = value
# _name2index(dict::OrderedDict{K,Int}, name::K) where K = dict[name]
#
# function _name2index(dict::OrderedDict{K,Int}, names::AbstractArray{K,N}) where {K,N}
#     index = similar(names, Int)
#     @inbounds for i in eachindex(names)
#         index[i] = dict[names[i]]
#     end
#     index
# end
#
# function _name2index(dict::OrderedDict{K,Int}, i::Not{K}) where K
#     setdiff(1:length(dict), dict[i.index])
# end
# _name2index(dict::OrderedDict{K,Int}, name::Name{K}) where K = dict[name.name]
