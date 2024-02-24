export  Rectifier,
        square, dsquare, d2square, SquareRectifier,
        ExpRectifier,
        softplus, dsoftplus, d2softplus, invsoftplus, SoftplusRectifier,
        sigmoid, dsigmoid, d2sigmoid, invsigmoid, SigmoidRectifier,
        flexsigmoid, dflexsigmoid, d2flexsigmoid, invflexsigmoid, FlexSigmoidRectifier,
        explinearunit, dexplinearunit, d2explinearunit, invexplinearunit, ELURectifier,
        inverse!, inverse, vinverse,
        grad_x!, grad_x, vgrad_x,
        grad_x_logeval, grad_x_logeval!, vgrad_x_logeval,
        hess_x_logeval, hess_x_logeval!, vhess_x_logeval,
        hess_x!, hess_x, vhess_x,
        evaluate!, vevaluate

"""
$(TYPEDEF)

This structure defines a continuous rectifier g,
i.e. a positive and monotonically increasing function
(e.g. square function, exponential , softplus, explinearunit).

## Fields

$(TYPEDFIELDS)

"""
struct Rectifier
    T::Symbol
    g::Function
    dg::Function
    d2g::Function
    invg::Function
end

function Rectifier(T::Symbol)
    return Rectifier(T, eval(T), eval(Symbol(:d, T)), eval(Symbol(:d2, T)), eval(Symbol(:inv, T)))
end

# Default rectifier is the softplus
Rectifier() = Rectifier(:softplus)

# Square rectifier
square(x) = x^2
dsquare(x) = 2.0*x
d2square(x) = 2.0
invsquare(x) = √(x)
const SquareRectifier = Rectifier(:square, square, dsquare, d2square, invsquare)

# Exponential Rectifier
const ExpRectifier = Rectifier(:exp, exp, exp, exp, log)

# Softplus rectifier
softplus(x) = (log(1.0 + exp(-abs(log(2.0)*x))) + max(log(2.0)*x, 0.0))/log(2.0)
dsoftplus(x) = 1/(1 + exp(-log(2.0)*x))
d2softplus(x) = log(2.0)/(2.0*(1.0 + cosh(log(2.0)*x)))
invsoftplus(x) = min(log(exp(log(2.0)*x) - 1.0)/log(2.0), x)
const SoftplusRectifier = Rectifier(:softplus, softplus, dsoftplus, d2softplus, invsoftplus)

# Sigmoid rectifier, implementation based on NNlib.jl to avoid underflow errors.
function sigmoid(x)
    t = exp(-abs(x))
    ifelse(x ≥ 0, inv(1 + t), t / (1 + t))
end
function dsigmoid(x)
    σ = sigmoid(x)
    return σ*(1-σ)
end
function d2sigmoid(x)
    σ = sigmoid(x)
    # from dσ*(1-σ) - σ*dσ
    return σ*(1-σ)*(1-2*σ) 
end
invsigmoid(x) = ifelse(x > 0, log(x) - log(1-x), "Not defined for x ≤ 0 ")
const SigmoidRectifier = Rectifier(:sigmoid, sigmoid, dsigmoid, d2sigmoid, invsigmoid)

# Parametric family of sigmoid with derivative bounded between Kmin > 0 and Kmax
function flexsigmoid(x, Kmin, Kmax)
    return Kmin + (Kmax-Kmin) * sigmoid(x)
end

function dflexsigmoid(x, Kmin, Kmax)
    σ = sigmoid(x)
    return (Kmax-Kmin)*σ*(1-σ)
end

function d2flexsigmoid(x, Kmin, Kmax)
    σ = sigmoid(x)
    return (Kmax-Kmin) * σ*(1-σ)*(1-2*σ) 
end

function invflexsigmoid(x, Kmin, Kmax)
    if x > Kmin && x < Kmax
        return log(x-Kmin) - log(Kmax-x)
    else
        return "Not defined for x outside [Kmin, Kmax]"
    end
end

function FlexSigmoidRectifier(Kmin = 1e-3, Kmax = 1e2) 
    @assert Kmin > 0 && Kmax > 0 && Kmax - Kmin > 0
    T = :flexsigmoid
    return Rectifier(T, x-> eval(T)(x, Kmin, Kmax), x->eval(Symbol(:d, T))(x, Kmin, Kmax), x->eval(Symbol(:d2, T))(x, Kmin, Kmax), x->eval(Symbol(:inv, T))(x, Kmin, Kmax))
end

# Exponential Linear Unit
explinearunit(x) = x < 0.0 ? exp(x) : x + 1.0
dexplinearunit(x) = x < 0.0 ? exp(x) : 1.0
d2explinearunit(x) = x < 0.0 ? exp(x) : 0.0
invexplinearunit(x) = x < 1.0 ? log(x) : x - 1.0
const ELURectifier = Rectifier(:explinearunit, explinearunit, dexplinearunit, d2explinearunit, invexplinearunit)

# Define convenient routines to work with rectifiers
(g::Rectifier)(x) = g.g(x)

function evaluate!(result, g::Rectifier, x)
    @assert size(result,1) == size(x,1) "Dimension of result and x don't match"
    vmap!(g.g, result, x)
end

vevaluate(g::Rectifier, x) = evaluate!(zero(x), g, x)


function inverse(g::Rectifier, x)
    @assert x>=0 "Input to rectifier is negative"
    return  g.invg(x)
end

function inverse!(result, g::Rectifier, x)
    @assert all(x .> 0) "Input to rectifier is negative"
    @assert size(result,1) == size(x,1) "Dimension of result and x don't match"
    vmap!(g.ginv, result, x)
    return result
end

vinverse(g::Rectifier, x)  = inverse!(zero(x), g, x)

grad_x(g::Rectifier, x) = g.dg(x)


function grad_x!(result, g::Rectifier, x)
    @assert size(result,1) == size(x, 1) "Dimension of result and x don't match"
    vmap!(g.dg, result, x)
    return result
end

vgrad_x(g::Rectifier, x) = grad_x!(zero(x), g, x)

""" Compute g′(x)/g(x) i.e d/dx log(g(x))"""
function grad_x_logeval(g::Rectifier, x::T) where {T <: Real}
    return g.dg(x)/g.g(x)
end

function grad_x_logeval!(result, g::Rectifier, x)
    @assert size(result,1) == size(x,1) "Dimension of result and x don't match"
    vmap!(xi->g.dg(xi)/g.g(xi), result, x)
    return result
end

vgrad_x_logeval(g::Rectifier, x) = grad_x_logeval!(zero(x), g, x)


# Compute (g″(x)g(x)-g′(x)^2)/g(x) i.e d^2/dx^2 log(g(x))
function hess_x_logeval(g::Rectifier, x::T) where {T <: Real}
    gx = g(x)
    dgx = g.dg(x)
    d2gx = g.d2g(x)
    return (d2gx*gx - dgx^2)/gx^2
end

function hess_x_logeval!(result, g::Rectifier, x)
    @assert size(result,1) == size(x,1) "Dimension of result and x don't match"
    vmap!(xi->(g.d2g(xi)*g(xi) - g.dg(xi)^2)/g(xi)^2, result, x)
    return result
end

vhess_x_logeval(g::Rectifier, x) = hess_x_logeval!(zero(x), g, x)

hess_x(g::Rectifier, x::T) where {T <: Real} = g.d2g(x)

function hess_x!(result, g::Rectifier, x)
    @assert size(result,1) == size(x,1) "Dimension of result and x don't match"
    vmap!(g.d2g, result, x)
    return result
end

vhess_x(g::Rectifier, x) = hess_x!(zero(x), g, x)
