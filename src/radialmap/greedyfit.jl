export greedyfit, gradient_off!, update_component!

function greedyfit(Nx, p::Int64, X, maxterms::Int64, λ, δ, γ)

    NxX, Ne = size(X)
    Xsort = deepcopy(sort(X; dims = 2))
    @assert p > -1 "Treat this particular case later"
    @assert λ == 0 "Greedy fit is only implemented for λ = 0"
    @assert NxX == Nx "Wrong dimension of the ensemble matrix `X`"
    @assert Nx > 1 "Treat this particular case later"
    # Initialize a sparse radial map component C with only a diagonal term of order p
    order = -1*ones(Int64, Nx)
    order[end] = p
    C = SparseRadialMapComponent(Nx, order)

    center_std!(C, X; γ = γ)
    x_diag = optimize(C, X, λ, δ)
    modify_a!(x_diag, C)


    # Create a radial map with order p for all the entries
    Cfull = SparseRadialMapComponent(Nx, p)

    # Compute centers and widths
    center_std!(Cfull, Xsort)

    ### Evaluate the different basis

    # Create weights
    ψ_off, ψ_diag, dψ_diag = compute_weights(Cfull, X)
    n_off = size(ψ_off,1)
    n_diag = size(ψ_diag,1)

    A = zeros(n_diag,n_diag)

    # Normalize diagtone basis functions
    μψ = mean(ψ_diag, dims=2)
    σψ = std(ψ_diag, dims=2, corrected=false)
    ψ_diagscaled = copy(ψ_diag)
    dψ_diagscaled = copy(dψ_diag)

    ψ_diagscaled .-= μψ
    ψ_diagscaled ./= σψ
    dψ_diagscaled ./= σψ

    if Nx == 1
        BLAS.gemm!('N', 'T', 1/Ne, ψ_diagscaled, ψ_diagscaled, 1.0, A)
    else
        ψ_offscaled = copy(ψ_off)

        μψ_off = mean(ψ_off, dims = 2)
        # σψ_off = std(ψ_off, dims = 2, corrected = false)
        σψ_off = norm.(eachslice(ψ_off; dims = 1))

        ψ_offscaled .-= μψ_off
        ψ_offscaled ./= σψ_off
    end

    # rhs = -ψ_diag x_diag
    rhs = zeros(Ne)
    mul!(rhs, ψdiag, -view(x_diag,2:end))
    rhs .-= x_diag[1]

    # Create updatable QR factorization
    # For the greedy optimization, we don't use a L2 regularization λ||x||^2,
    # since we are already making a greedy selection of the features
    F = qrfactUnblocked(zeros(0,0))
    # Off-diagonal coefficients will be permuted based on the greedy procedure

    candidates = collect(1:Nx-1)
    # Unordered off-diagonal active dimensions
    offdims = Int64[]

    # Compute the gradient of the different basis
    dJ = zeros((p+1)*(Nx-1))

    x_off = zeros((p+1)*(Nx-1))

    # maxfmaily is the maximal number of
    if p == 0
        maxfamily = ceil(Int64, (sqrt(Ne)-(p+1))/(p+1))
    elseif p > 0
        maxfamily = ceil(Int64, (sqrt(Ne)-(p+3))/(p+1))
    else
        error("Wrong value for p")
    end

    budget = min(maxfamily, Nx-1)
    count = 0
    # Compute the norm of the different candidate features
    sqnormfeatures = map(i-> norm(view(ψ_off, (i-1)*(p+1)+1:i*(p+1)))^2, candidate)
    cache = zeros(Ne)
    for i=1:budget
        # Compute the gradient of the different basis (use the unscaled basis evaluations)
        mul!(rhs, ψdiag, -view(x_diag,2:end))
        rhs .-= x_diag[1]
        gradient_off!(dJ, cache, ψ_off, x_off, rhs, Ne)

        _, new_dim = findmax(map(i-> norm(view(dJ, (i-1)*(p+1)+1:i*(p+1)))^2/sqnormfeatures[i], candidate))
        push!(offdims, copy(new_dim))

        # Update storage in C
        update_component!(C, p, new_dim)

        # Compute center and std for this new family of features
        # The centers and widths have already been computed in Cfull
        copy!(C.ξ[new_dim], Cfull.ξ[new_dim])
        copy!(C.σ[new_dim], Cfull.σ[new_dim])

        # Then update qr, then do change of variables
        x_opt = optimize(C, X, λ, δ)
        modify_a!(C, x_opt)

        # Make sure that active dim are in the right order when we affect coefficient.
        # For the split and kfold compute the training and validation losses.
        copy!(x_diag, x_opt[end-nd+1:end])


        # for (j, offdimj) in enumerate(offdims)
        #     x_off[(j-1)*(p+1)+1:i*(p+1)))] .= copy(x_opt[])
        # end
        filter!(x-> x!= new_dim, candidate)
    end
end

function gradient_off!(dJ::AbstractVector{Float64}, cache::AbstractVector{Float64}, ψ_off::AbstractMatrix{Float64}, x_off, rhs, Ne::Int64)
    fill!(dJ, 0.0)
    cache .= ψ_off*x_off
    cache .-= rhs
    dJ .= (1/Ne)*ψ_off*cache
end

gradient_off!(dJ::AbstractVector{Float64}, ψ_off::AbstractMatrix{Float64}, x_off, rhs, Ne::Int64) =
              gradient_off!(dJ, zeros(Ne), ψ_off, x_off, rhs, Ne)


function update_component!(C::SparseRadialMapComponent, p::Int64, new_dim::Int64)
    @assert C.Nx >= newdim
    if newdim == C.Nx
        if p == -1
            C.p[new_dim] = p
            C.ξ[new_dim] = Float64[]
            C.σ[new_dim] = Float64[]
            C.a[new_dim] = Float64[]
        elseif p == 0
            C.p[new_dim] = p
            push!(C.activedim, new_dim)
            sort!(C.activedim)
            C.ξ[new_dim] = zeros(p)
            C.σ[new_dim] = zeros(p)
            C.a[new_dim] = zeros(p+2)
        else
            C.p[new_dim] = p
            push!(C.activedim, new_dim)
            sort!(C.activedim)
            C.ξ[new_dim] = zeros(p+2)
            C.σ[new_dim] = zeros(p+2)
            C.a[new_dim] = zeros(p+3)
        end
    else
        if p == -1
            C.p[new_dim] = p
            C.ξ[new_dim] = Float64[]
            C.σ[new_dim] = Float64[]
            C.a[new_dim] = Float64[]
        elseif p == 0
            C.p[new_dim] = p
            push!(C.activedim, new_dim)
            sort!(C.activedim)
            C.ξ[new_dim] = zeros(p)
            C.σ[new_dim] = zeros(p)
            C.a[new_dim] = zeros(p+1)
        else
            C.p[new_dim] = p
            push!(C.activedim, new_dim)
            sort!(C.activedim)
            C.ξ[new_dim] = zeros(p+1)
            C.σ[new_dim] = zeros(p+1)
            C.a[new_dim] = zeros(p+2)
        end
    end
end