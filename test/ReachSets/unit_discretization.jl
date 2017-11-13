import Reachability.ReachSets.discretize

# ===================================================================
# Discretization of a continuous-time system without input (VoidSet)
# ===================================================================
A = sparse([1, 1, 2, 3, 4], [1, 2, 2, 4, 3], [1., 2., 3., 4., 5.], 4, 4)
X0 = BallInf(zeros(4), 0.1)
cont_sys_homog = ContinuousSystem(A, X0)
δ = 0.01

# no bloating, do not use Pade approximation
discr_sys_homog = discretize(cont_sys_homog, δ, approx_model="nobloating", pade_expm=false)
@test length(discr_sys_homog.U) == 1
input_state = start(discr_sys_homog.U)
@test isa(input_state.sf, VoidSet) && dim(input_state.sf) == 4

# no bloating, use Pade approximation
discr_sys_homog = discretize(cont_sys_homog, δ, approx_model="nobloating", pade_expm=true)

# bloating, do not use Pade approximation
discr_sys_homog = discretize(cont_sys_homog, δ, pade_expm=false)

# bloating, use Pade approximation
discr_sys_homog = discretize(cont_sys_homog, δ, pade_expm=true)

# ===============================================================
# Discretization of a continuous-time system with constant input
# ===============================================================
U = Ball2(ones(4), 0.5)
cont_sys = ContinuousSystem(A, X0, U)

# no bloating, do not use Pade approximation
discr_sys = discretize(cont_sys, δ, approx_model="nobloating", pade_expm=false)
@test length(discr_sys.U) == 1
input_state = start(discr_sys.U)
@test dim(input_state.sf) == 4
@test isa(input_state.sf, LinearMap)
@test isa(input_state.sf.sf, Ball2) && input_state.sf.sf.center == ones(4) && input_state.sf.sf.radius == 0.5

# no bloating, use Pade approximation
discr_sys = discretize(cont_sys, δ, approx_model="nobloating", pade_expm=true)

# bloating, do not use Pade approximation
discr_sys = discretize(cont_sys, δ, pade_expm=false)
@test length(discr_sys.U) == 1
input_state = start(discr_sys.U)
@test dim(input_state.sf) == 4
@test isa(input_state.sf, MinkowskiSum)

# bloating, use Pade approximation
discr_sys = discretize(cont_sys, δ, pade_expm=true)

# us
discr_sys = discretize(cont_sys, δ, approx_model="firstorder")

# ===================================================================
# Discretization of a continuous-time system with time-varying input
# ===================================================================
Ui = [Ball2(0.01*i*ones(4), i*0.2) for i in 1:3]
cont_sys = ContinuousSystem(A, X0, Ui)

# no bloating, do not use Pade approximation
discr_sys = discretize(cont_sys, δ, approx_model="nobloating", pade_expm=false)
@test length(discr_sys.U) == 3

input_state = start(discr_sys.U)
@test dim(input_state.sf) == 4
@test isa(input_state.sf, LinearMap)
@test isa(input_state.sf.sf, Ball2) && input_state.sf.sf.center == 0.01*ones(4) && input_state.sf.sf.radius == 0.2

input_state = next(discr_sys.U, input_state)
@test dim(input_state.sf) == 4
@test isa(input_state.sf, LinearMap)
@test isa(input_state.sf.sf, Ball2) && input_state.sf.sf.center == 0.01*2*ones(4) && input_state.sf.sf.radius == 0.2*2

input_state = next(discr_sys.U, input_state)
@test dim(input_state.sf) == 4
@test isa(input_state.sf, LinearMap)
@test isa(input_state.sf.sf, Ball2) && input_state.sf.sf.center == 0.01*3*ones(4) && input_state.sf.sf.radius == 0.2*3

# no bloating, use Pade approximation
discr_sys = discretize(cont_sys, δ, approx_model="nobloating", pade_expm=true)

# bloating, do not use Pade approximation
discr_sys = discretize(cont_sys, δ, pade_expm=false)
@test length(discr_sys.U) == 3

input_state = start(discr_sys.U)
@test dim(input_state.sf) == 4
@test isa(input_state.sf, MinkowskiSum)
@test isa(input_state.sf.X.sf, Ball2) && input_state.sf.X.sf.center == 0.01*ones(4) && input_state.sf.X.sf.radius == 0.2

input_state = next(discr_sys.U, input_state)
@test dim(input_state.sf) == 4
@test isa(input_state.sf, MinkowskiSum)
@test isa(input_state.sf.X.sf, Ball2) && input_state.sf.X.sf.center == 0.01*2*ones(4) && input_state.sf.X.sf.radius == 0.2*2

input_state = next(discr_sys.U, input_state)
@test dim(input_state.sf) == 4
@test isa(input_state.sf, MinkowskiSum)
@test isa(input_state.sf.X.sf, Ball2) && input_state.sf.X.sf.center == 0.01*3*ones(4) && input_state.sf.X.sf.radius == 0.2*3

# bloating, use Pade approximation
discr_sys = discretize(cont_sys, δ, pade_expm=true)
