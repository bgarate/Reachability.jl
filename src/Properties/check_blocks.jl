#=
    check_blocks(ϕ, Xhat0, U, overapproximate, n, b, N, blocks, prop)

Property checking of a given number of two-dimensional blocks of an affine
system with nondeterministic inputs.

The variants have the following structure:

INPUT:

- `ϕ` -- sparse matrix of a discrete affine system
- `Xhat0` -- initial set as a cartesian product over 2d blocks
- `U` -- input set of undeterministic inputs
- `overapproximate_inputs` -- function for overapproximation of inputs
- `n` -- ambient dimension
- `N` -- number of sets computed
- `blocks` -- the block indices to be computed
- `partition` -- the partition into blocks
- `prop` -- property to be checked

OUTPUT:

The first time index where the property is violated, and 0 if the property is satisfied.
=#

# helper functions
@inline proj(bi::UnitRange{Int}, n::Int) =
         sparse(1:length(bi), bi, ones(length(bi)), length(bi), n)
@inline proj(bi::Int, n::Int) = sparse([1], [bi], ones(1), 1, n)
@inline row(ϕpowerk::AbstractMatrix, bi::UnitRange{Int}) = ϕpowerk[bi, :]
@inline row(ϕpowerk::AbstractMatrix, bi::Int) = ϕpowerk[[bi], :]
@inline row(ϕpowerk::SparseMatrixExp, bi::UnitRange{Int}) = get_rows(ϕpowerk, bi)
@inline row(ϕpowerk::SparseMatrixExp, bi::Int) = Matrix(get_row(ϕpowerk, bi))
@inline block(ϕpowerk_πbi::AbstractMatrix, bj::UnitRange{Int}) = ϕpowerk_πbi[:, bj]
@inline block(ϕpowerk_πbi::AbstractMatrix, bj::Int) = ϕpowerk_πbi[:, [bj]]

# sparse
function check_blocks(ϕ::SparseMatrixCSC{NUM, Int},
                       Xhat0::Vector{<:LazySet{NUM}},
                       U::Union{ConstantInput, Void},
                       overapproximate_inputs::Function,
                       n::Int,
                       N::Int,
                       blocks::AbstractVector{Int},
                       partition::AbstractVector{<:Union{AbstractVector{Int}, Int}},
                       eager_checking::Bool,
                       prop::Property
                       )::Int where {NUM}
    violation_index = 0
    if !check_property(CartesianProductArray(Xhat0[blocks]), prop)
        if eager_checking
            return 1
        end
        violation_index = 1
    elseif N == 1
        return 0
    end

    b = length(blocks)
    Xhatk = Vector{LazySet{NUM}}(b)
    ϕpowerk = copy(ϕ)

    if U != nothing
        Whatk = Vector{LazySet{NUM}}(b)
        inputs = next_set(U)
        @inbounds for i in 1:b
            bi = partition[blocks[i]]
            Whatk[i] = overapproximate_inputs(1, blocks[i], proj(bi, n) * inputs)
        end
    end

    k = 2
    p = Progress(N, 1, "Computing successors ")
    @inbounds while true
        update!(p, k)
        for i in 1:b
            bi = partition[blocks[i]]
            Xhatk_bi = ZeroSet(length(bi))
            for (j, bj) in enumerate(partition)
                block = ϕpowerk[bi, bj]
                if findfirst(block) != 0
                    Xhatk_bi = Xhatk_bi + block * Xhat0[j]
                end
            end
            Xhatk[i] = (U == nothing ? Xhatk_bi : Xhatk_bi + Whatk[i])
        end

        if !check_property(CartesianProductArray(Xhatk), prop)
            if eager_checking
                return k
            elseif violation_index == 0
                violation_index = k
            end
            if k == N
                break
            end
        elseif k == N
            break
        end

        if U != nothing
            for i in 1:b
                bi = partition[blocks[i]]
                Whatk[i] = overapproximate_inputs(k, blocks[i],
                    Whatk[i] + row(ϕpowerk, bi) * inputs)
            end
        end

        ϕpowerk = ϕpowerk * ϕ
        k += 1
    end

    return violation_index
end

# dense
function check_blocks(ϕ::AbstractMatrix{NUM},
                       Xhat0::Vector{<:LazySet{NUM}},
                       U::Union{ConstantInput, Void},
                       overapproximate_inputs::Function,
                       n::Int,
                       N::Int,
                       blocks::AbstractVector{Int},
                       partition::AbstractVector{<:Union{AbstractVector{Int}, Int}},
                       eager_checking::Bool,
                       prop::Property
                       )::Int where {NUM}
    violation_index = 0
    if !check_property(CartesianProductArray(Xhat0[blocks]), prop)
        if eager_checking
            return 1
        end
        violation_index = 1
    elseif N == 1
        return 0
    end

    b = length(blocks)
    Xhatk = Vector{LazySet{NUM}}(b)
    ϕpowerk = copy(ϕ)
    ϕpowerk_cache = similar(ϕ)

    if U != nothing
        Whatk = Vector{LazySet{NUM}}(b)
        inputs = next_set(U)
        @inbounds for i in 1:b
            bi = partition[blocks[i]]
            Whatk[i] = overapproximate_inputs(1, blocks[i], proj(bi, n) * inputs)
        end
    end

    arr_length = (U == nothing) ? length(partition) : length(partition) + 1
    k = 2
    p = Progress(N, 1, "Computing successors ")
    @inbounds while true
        update!(p, k)
        for i in 1:b
            bi = partition[blocks[i]]
            arr = Vector{LazySet{NUM}}(arr_length)
            for (j, bj) in enumerate(partition)
                arr[j] = ϕpowerk[bi, bj] * Xhat0[j]
            end
            if U != nothing
                arr[arr_length] = Whatk[i]
            end
            Xhatk[i] = MinkowskiSumArray(arr)
        end

        if !check_property(CartesianProductArray(Xhatk), prop)
            if eager_checking
                return k
            elseif violation_index == 0
                violation_index = k
            end
            if k == N
                break
            end
        elseif k == N
            break
        end

        if U != nothing
            for i in 1:b
                bi = partition[blocks[i]]
                Whatk[i] = overapproximate_inputs(k, blocks[i],
                    Whatk[i] + row(ϕpowerk, bi) * inputs)
            end
        end

        A_mul_B!(ϕpowerk_cache, ϕpowerk, ϕ)
        copy!(ϕpowerk, ϕpowerk_cache)
        k += 1
    end

    return violation_index
end

# lazy_expm sparse
function check_blocks(ϕ::SparseMatrixExp{NUM},
                       assume_sparse::Val{true},
                       Xhat0::Vector{<:LazySet{NUM}},
                       U::Union{ConstantInput, Void},
                       overapproximate_inputs::Function,
                       n::Int,
                       N::Int,
                       blocks::AbstractVector{Int},
                       partition::AbstractVector{<:Union{AbstractVector{Int}, Int}},
                       eager_checking::Bool,
                       prop::Property
                       )::Int where {NUM}
    violation_index = 0
    if !check_property(CartesianProductArray(Xhat0[blocks]), prop)
        if eager_checking
            return 1
        end
        violation_index = 1
    elseif N == 1
        return 0
    end

    b = length(blocks)
    Xhatk = Vector{LazySet{NUM}}(b)
    ϕpowerk = SparseMatrixExp(copy(ϕ.M))

    if U != nothing
        Whatk = Vector{LazySet{NUM}}(b)
        inputs = next_set(U)
        @inbounds for i in 1:b
            bi = partition[blocks[i]]
            Whatk[i] = overapproximate_inputs(1, blocks[i], proj(bi, n) * inputs)
        end
    end

    k = 2
    p = Progress(N, 1, "Computing successors ")
    @inbounds while true
        update!(p, k)
        for i in 1:b
            bi = partition[blocks[i]]
            ϕpowerk_πbi = row(ϕpowerk, bi)
            Xhatk_bi = ZeroSet(length(bi))
            for (j, bj) in enumerate(partition)
                πbi = block(ϕpowerk_πbi, bj)
                if findfirst(πbi) != 0
                    Xhatk_bi = Xhatk_bi + πbi * Xhat0[j]
                end
            end
            Xhatk[i] = (U == nothing ? Xhatk_bi : Xhatk_bi + Whatk[i])
            if U != nothing
                Whatk[i] = overapproximate_inputs(k, blocks[i],
                    Whatk[i] + ϕpowerk_πbi * inputs)
            end
        end

        if !check_property(CartesianProductArray(Xhatk), prop)
            if eager_checking
                return k
            elseif violation_index == 0
                violation_index = k
            end
            if k == N
                break
            end
        elseif k == N
            break
        end

        ϕpowerk.M .= ϕpowerk.M + ϕ.M
        k += 1
    end

    return violation_index
end

# lazy_expm dense
function check_blocks(ϕ::SparseMatrixExp{NUM},
                       assume_sparse::Val{false},
                       Xhat0::Vector{<:LazySet{NUM}},
                       U::Union{ConstantInput, Void},
                       overapproximate_inputs::Function,
                       n::Int,
                       N::Int,
                       blocks::AbstractVector{Int},
                       partition::AbstractVector{<:Union{AbstractVector{Int}, Int}},
                       eager_checking::Bool,
                       prop::Property
                       )::Int where {NUM}
    violation_index = 0
    if !check_property(CartesianProductArray(Xhat0[blocks]), prop)
        if eager_checking
            return 1
        end
        violation_index = 1
    elseif N == 1
        return 0
    end

    b = length(blocks)
    Xhatk = Vector{LazySet{NUM}}(b)
    ϕpowerk = SparseMatrixExp(copy(ϕ.M))

    if U != nothing
        Whatk = Vector{LazySet{NUM}}(b)
        inputs = next_set(U)
        @inbounds for i in 1:b
            bi = partition[blocks[i]]
            Whatk[i] = overapproximate_inputs(1, blocks[i], proj(bi, n) * inputs)
        end
    end

    arr_length = (U == nothing) ? length(partition) : length(partition) + 1
    k = 2
    p = Progress(N, 1, "Computing successors ")
    @inbounds while true
        update!(p, k)
        for i in 1:b
            bi = partition[blocks[i]]
            arr = Vector{LazySet{NUM}}(arr_length)
            ϕpowerk_πbi = row(ϕpowerk, bi)
            for (j, bj) in enumerate(partition)
                arr[j] = block(ϕpowerk_πbi, bj) * Xhat0[j]
            end
            if U != nothing
                arr[arr_length] = Whatk[i]
            end
            Xhatk[i] = MinkowskiSumArray(arr)
            if U != nothing
                Whatk[i] = overapproximate_inputs(k, blocks[i],
                    Whatk[i] + ϕpowerk_πbi * inputs)
            end
        end

        if !check_property(CartesianProductArray(Xhatk), prop)
            if eager_checking
                return k
            elseif violation_index == 0
                violation_index = k
            end
            if k == N
                break
            end
        elseif k == N
            break
        end

        ϕpowerk.M .= ϕpowerk.M + ϕ.M
        k += 1
    end

    return violation_index
end
