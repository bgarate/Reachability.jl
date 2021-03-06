"""
    discretize(cont_sys, δ; [approx_model], [pade_expm], [lazy_expm], [lazy_sih])

Discretize a continuous system of ODEs with nondeterministic inputs.

## Input

- `cont_sys`     -- continuous system
- `δ`            -- step size
- `approx_model` -- the method to compute the approximation model for the
                    discretization, among:

    - `forward`    -- use forward-time interpolation
    - `backward`   -- use backward-time interpolation
    - `firstorder` -- use first order approximation of the ODE
    - `nobloating` -- do not bloat the initial states
                      (use for discrete-time reachability)

- `pade_expm`    -- (optional, default = `false`) if true, use Pade approximant
                    method to compute matrix exponentials of sparse matrices;
                    otherwise use Julia's buil-in `expm`
- `lazy_expm`    -- (optional, default = `false`) if true, compute the matrix
                    exponential in a lazy way (suitable for very large systems)
- `lazy_sih`     -- (optional, default = `true`) if true, compute the
                    symmetric interval hull in a lazy way (suitable if only a
                    few dimensions are of interest)

## Output

A discrete system.

## Notes

This function applies an approximation model to transform a continuous affine
system into a discrete affine system.
This transformation allows to do dense time reachability, i.e. such that the
trajectories of the given continuous system are included in the computed
flowpipe of the discretized system.
For discrete-time reachability, use `approx_model="nobloating"`.
"""
function discretize(cont_sys::InitialValueProblem{<:AbstractContinuousSystem},
                    δ::Float64;
                    approx_model::String="forward",
                    pade_expm::Bool=false,
                    lazy_expm::Bool=false,
                    lazy_sih::Bool=true,
                    parallel::Bool=false)::InitialValueProblem{<:AbstractDiscreteSystem}

    if(parallel)
        info("Parallel discretize")
    end

    if approx_model in ["forward", "backward"]
        return discr_bloat_interpolation(cont_sys, δ, approx_model, pade_expm,
                                         lazy_expm, lazy_sih, parallel)
    elseif approx_model == "firstorder"
        return discr_bloat_firstorder(cont_sys, δ, parallel)
    elseif approx_model == "nobloating"
        return discr_no_bloat(cont_sys, δ, pade_expm, lazy_expm, parallel)
    else
        error("The approximation model is invalid")
    end
end

"""
    bloat_firstorder(cont_sys, δ)

Compute bloating factors using first order approximation.

## Input

- `cont_sys` -- a continuous affine system
- `δ`        -- step size

## Notes

In this algorithm, the infinity norm is used.
See also: `discr_bloat_interpolation` for more accurate (less conservative)
bounds.

## Algorithm

This uses a first order approximation of the ODE, and matrix norm upper bounds,
see Le Guernic, C., & Girard, A., 2010, *Reachability analysis of linear systems
using support functions. Nonlinear Analysis: Hybrid Systems, 4(2), 250-262.*
"""
function discr_bloat_firstorder(cont_sys::InitialValueProblem{<:AbstractContinuousSystem},
                                δ::Float64, parallel::Bool)

    if(parallel)
        error("Not implemented");
    end

    A, X0 = cont_sys.s.A, cont_sys.x0
    Anorm = norm(full(A), Inf)
    ϕ = expm(full(A))
    RX0 = norm(X0, Inf)

    if inputdim(cont_sys) == 0
        # linear case
        α = (exp(δ*Anorm) - 1. - δ*Anorm) * RX0
        Ω0 = CH(X0, ϕ * X0 + Ball2(zeros(size(ϕ, 1)), α))
        return DiscreteSystem(ϕ, Ω0)
    else
        # affine case; TODO: unify Constant and Varying input branches?
        Uset = inputset(cont_sys)
        if Uset isa ConstantInput
            U = next(Uset, 1)[1]
            RU = norm(U, Inf)
            α = (exp(δ*Anorm) - 1. - δ*Anorm)*(RX0 + RU/Anorm)
            β = (exp(δ*Anorm) - 1. - δ*Anorm)*RU/Anorm
            Ω0 = CH(X0, ϕ * X0 + δ * U + Ball2(zeros(size(ϕ, 1)), α))
            discr_U =  δ * U + Ball2(zeros(size(ϕ, 1)), β)
            return DiscreteSystem(ϕ, Ω0, discr_U)
        elseif Uset isa VaryingInput
            discr_U = Vector{LazySet}(length(Uset))
            for (i, Ui) in enumerate(Uset)
                RU = norm(Ui, Inf)
                α = (exp(δ*Anorm) - 1. - δ*Anorm)*(RX0 + RU/Anorm)
                β = (exp(δ*Anorm) - 1. - δ*Anorm)*RU/Anorm
                Ω0 = CH(X0, ϕ * X0 + δ * Ui + Ball2(zeros(size(ϕ, 1)), α))
                discr_U[i] =  δ * Ui + Ball2(zeros(size(ϕ, 1)), β)
            end
            return DiscreteSystem(ϕ, Ω0, discr_U)
        end
    end


end

"""
    discr_no_bloat(cont_sys, δ, pade_expm, lazy_expm)

Discretize a continuous system without bloating of the initial states, suitable
for discrete-time reachability.

## Input

- `cont_sys`     -- a continuous system
- `δ`            -- step size
- `pade_expm`    -- if `true`, use Pade approximant method to compute the
                    matrix exponential
- `lazy_expm`    -- if `true`, compute the matrix exponential in a lazy way
                    (suitable for very large systems)

## Output

A discrete system.

## Algorithm

The transformation implemented here is the following:

- `A -> Phi := exp(A*delta)`
- `U -> V := M*U`
- `X0 -> X0hat := X0`

where `M` corresponds to `Phi1(A, delta)` in Eq. (8) of *SpaceEx: Scalable
Verification of Hybrid Systems.*

In particular, there is no bloating, i.e. we don't bloat the initial states and
dont multiply the input by the step size δ, as required for the dense time case.
"""
function discr_no_bloat(cont_sys::InitialValueProblem{<:AbstractContinuousSystem},
                        δ::Float64,
                        pade_expm::Bool,
                        lazy_expm::Bool,
                        parallel::Bool)

    if(parallel)
        error("Not implemented");
    end

    A, X0 = cont_sys.s.A, cont_sys.x0
    n = size(A, 1)

    if lazy_expm
        ϕ = SparseMatrixExp(A * δ)
    else
        if pade_expm
            ϕ = padm(A * δ)
        else
            ϕ = expm(full(A * δ))
        end
    end

    # early return for homogeneous systems
    if cont_sys isa IVP{<:LinearContinuousSystem}
        Ω0 = X0
        return DiscreteSystem(ϕ, Ω0)
    end
    U = inputset(cont_sys)
    inputs = next_set(U, 1)

    # compute matrix to transform the inputs
    if lazy_expm
        P = SparseMatrixExp([A*δ sparse(δ*I, n, n) spzeros(n, n);
                             spzeros(n, 2*n) sparse(δ*I, n, n);
                             spzeros(n, 3*n)])
        Phi1Adelta = sparse(get_columns(P, (n+1):2*n)[1:n, :])
    else
        if pade_expm
            P = padm([A*δ sparse(δ*I, n, n) spzeros(n, n);
                      spzeros(n, 2*n) sparse(δ*I, n, n);
                      spzeros(n, 3*n)])
        else
            P = expm(full([A*δ sparse(δ*I, n, n) spzeros(n, n);
                           spzeros(n, 2*n) sparse(δ*I, n, n);
                           spzeros(n, 3*n)]))
        end
        Phi1Adelta = P[1:n, (n+1):2*n]
    end

    discretized_U = Phi1Adelta * inputs

    Ω0 = X0

    if U isa ConstantInput
        return DiscreteSystem(ϕ, Ω0, discretized_U)
    else
        discretized_U = VaryingInput([Phi1Adelta * Ui for Ui in U])
        return DiscreteSystem(ϕ, Ω0, discretized_U)
    end
end

"""
    discr_bloat_interpolation(cont_sys, δ, approx_model, pade_expm, lazy_expm)

Compute bloating factors using forward or backward interpolation.

## Input

- `cs`           -- a continuous system
- `δ`            -- step size
- `approx_model` -- choose the approximation model among `"forward"` and
                    `"backward"`
- `pade_expm`    -- if true, use Pade approximant method to compute the
                    matrix exponential
- `lazy_expm`   --  if true, compute the matrix exponential in a lazy way
                    suitable for very large systems)

## Algorithm

See Frehse et al., CAV'11, *SpaceEx: Scalable Verification of Hybrid Systems*,
Lemma 3.

Note that in the unlikely case that A is invertible, the result can also
be obtained directly, as a function of the inverse of A and `e^{At} - I`.

The matrix `P` is such that: `ϕAabs = P[1:n, 1:n]`,
`Phi1Aabsdelta = P[1:n, (n+1):2*n]`, and `Phi2Aabs = P[1:n, (2*n+1):3*n]`.
"""
function discr_bloat_interpolation(cont_sys::InitialValueProblem{<:AbstractContinuousSystem},
                                   δ::Float64,
                                   approx_model::String,
                                   pade_expm::Bool,
                                   lazy_expm::Bool,
                                   lazy_sih::Bool,
                                   parallel::Bool)

    if(parallel)
        info("Parallel discr_bloat_interpolation")
        sih = lazy_sih ? error("Not implemented") : symmetric_interval_hull_parallel
    else
        sih = lazy_sih ? SymmetricIntervalHull : symmetric_interval_hull
    end

    A, X0 = cont_sys.s.A, cont_sys.x0
    n = size(A, 1)

    # compute matrix ϕ = exp(Aδ)
    if lazy_expm
        ϕ = SparseMatrixExp(A*δ)
    else
        if pade_expm
            ϕ = padm(A*δ)
        else
            ϕ = expm(full(A*δ))
        end
    end

    # early return for homogeneous systems
    if cont_sys isa IVP{<:LinearContinuousSystem}
         Ω0 = CH(X0, ϕ * X0)
        return DiscreteSystem(ϕ, Ω0)
    end
    U = inputset(cont_sys)
    inputs = next_set(U, 1)

    # compute the transformation matrix to bloat the initial states
    if lazy_expm
        mat = [abs.(A*δ) sparse(δ*I, n, n) spzeros(n, n);
                             spzeros(n, 2*n) sparse(δ*I, n, n);
                             spzeros(n, 3*n)]
        P = SparseMatrixExp(mat)
        Phi2Aabs = sparse(get_columns(P, (2*n+1):3*n, parallel)[1:n, :])
    else
        if pade_expm
            P = padm([abs.(A*δ) sparse(δ*I, n, n) spzeros(n, n);
                      spzeros(n, 2*n) sparse(δ*I, n, n);
                      spzeros(n, 3*n)])
        else
            P = expm(full([abs.(A*δ) sparse(δ*I, n, n) spzeros(n, n);
                           spzeros(n, 2*n) sparse(δ*I, n, n);
                           spzeros(n, 3*n)]))
        end
        Phi2Aabs = P[1:n, (2*n+1):3*n]
    end

    if isa(inputs, ZeroSet)
        if approx_model == "forward" || approx_model == "backward"
            Ω0 = CH(X0, ϕ * X0 + δ * inputs)
        end
    else
        EPsi = sih(Phi2Aabs * sih(A * inputs))
        discretized_U = δ * inputs + EPsi
        if approx_model == "forward"
            EOmegaPlus = sih(Phi2Aabs * sih((A * A) * X0))
            Ω0 = CH(X0, ϕ * X0 + discretized_U + EOmegaPlus)
        elseif approx_model == "backward"
            EOmegaMinus = sih(Phi2Aabs * sih((A * A * ϕ) * X0))
            Ω0 = CH(X0, ϕ * X0 + discretized_U + EOmegaMinus)
        end
    end

    if U isa ConstantInput
        return DiscreteSystem(ϕ, Ω0, discretized_U)
    else
        discretized_U = [δ * Ui + sih(Phi2Aabs * sih(A * Ui)) for Ui in U]
        return DiscreteSystem(ϕ, Ω0, discretized_U)
    end
end
