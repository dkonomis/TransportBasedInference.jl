import Base: size, show, @propagate_inbounds


# Define the concept of basis functions, where each function is indexed by an integer
# For instance, (1, x, ψ0, ψ1,..., ψn) defines a basis where the index:
# 0 corresponds to the constant function
# 1 corresponds to the linear function
# n+2 corresponds to the n-th order physicist Hermite function

export Basis, CstPhyHermite, CstProHermite,
       CstLinPhyHermite, CstLinProHermite,
       vander!,
       vander


struct Basis{m}
    f::Array{ParamFcn,1}
    function Basis(f::Array{ParamFcn,1})
        return new{size(f,1)}(f)
    end
end


function CstPhyHermite(m::Int64; scaled::Bool = false)
    f = zeros(ParamFcn, m+2)
    # f[1] = 1.0
    f[1] = FamilyProPolyHermite[1]
    for i=0:m
        f[2+i] = PhyHermite(i; scaled = scaled)
    end
    return Basis(f)
end

function CstProHermite(m::Int64; scaled::Bool = false)
    f = zeros(ParamFcn, m+2)
    # f[1] = 1.0
    f[1] = FamilyProPolyHermite[1]
    for i=0:m
        f[2+i] = ProHermite(i; scaled = scaled)
    end
    return Basis(f)
end

function CstLinPhyHermite(m::Int64; scaled::Bool = false)
    f = zeros(ParamFcn, m+3)
    # f[1] = 1.0
    f[1] = FamilyProPolyHermite[1]
    # f[1] = x
    f[2] = FamilyProPolyHermite[2]
    for i=0:m
        f[3+i] = PhyHermite(i; scaled = scaled)
    end
    return Basis(f)
end

function CstLinProHermite(m::Int64; scaled::Bool = false)
    f = zeros(ParamFcn, m+3)
    # f[1] = 1.0
    f[1] = FamilyProPolyHermite[1]
    # f[1] = x
    f[2] = FamilyProPolyHermite[2]
    for i=0:m
        f[3+i] = ProHermite(i; scaled = scaled)
    end
    return Basis(f)
end

(F::Array{ParamFcn,1})(x::T) where {T <: Real} = map!(fi->fi(x), zeros(T, size(F,1)), F)
(B::Basis{m})(x::T) where {m, T<:Real} = B.f(x)

# (B::Basis{m})(x::T) where {m, T<:Real} = map!(fi->fi(x), zeros(T, m), B.f)

# @propagate_inbounds Base.getindex(F::Array{T,1}, i::Int) where {T<:ParamFcn} = getindex(F,i)
# @propagate_inbounds Base.setindex!(F::Array{T,1}, v::ParamFcn, i::Int) where {T<:ParamFcn} = setindex!(F,v,i)

@propagate_inbounds Base.getindex(B::Basis{m}, i::Int) where {m} = getindex(B.f,i)
@propagate_inbounds Base.setindex!(B::Basis{m}, v::ParamFcn, i::Int) where {m} = setindex!(B.f,v,i)

Base.size(B::Basis{m},d::Int) where {m} = size(B.f,d)
Base.size(B::Basis{m}) where {m} = size(B.f)

function Base.show(io::IO, B::Basis{m}) where {m}
    println(io,"Basis of "*string(m)*" functions:")
    for i=1:m
        println(io, B[i])
    end
end

function vander!(dV, B::Basis{m}, maxi::Int64, k::Int64, x) where {m}
    N = size(x,1)
    @assert size(dV) == (N, maxi+1) "Wrong dimension of the Vander matrix"
    @inbounds for i=1:maxi+1
        col = view(dV,:,i)

        if i==1
            if k==0
                fill!(col, 1.0)
            else
                fill!(col , 0.0)
            end
        else
            if typeof(B.f[i]) <: Union{PhyHermite, ProHermite}
                # Store the k-th derivative of the i-th order Hermite polynomial
                derivative!(col, B.f[i], k, x)
            elseif typeof(B[i]) <: Union{PhyPolyHermite, ProPolyHermite} && degree(B[i])>0
                    Pik = derivative(B.f[i], k)
                #     # In practice the first component of the basis will be constant,
                #     # so this is very cheap to construct the derivative vector
                    @. col = Pik(x)
            end
        end
    end
    return dV
end

vander!(dV, B::Basis{m}, k::Int64, x) where {m} = vander!(dV, B, m-1, k, x)

vander(B::Basis{m}, maxi::Int64, k::Int64, x) where {m} = vander!(zeros(size(x,1),maxi+1), B, maxi, k, x)
vander(B::Basis{m}, k::Int64, x) where {m} = vander!(zeros(size(x,1),m), B, k, x)
