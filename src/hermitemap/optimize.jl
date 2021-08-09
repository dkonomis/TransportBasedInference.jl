export optimize


function optimize(C::HermiteMapComponent, X, optimkind::Union{Nothing, Int64, String};
                  maxterms::Int64 = 100,
                  withconstant::Bool = false, withqr::Bool = false,
                  maxpatience::Int64 = 10^5, verbose::Bool = false,
                  hessprecond = true, P::Parallel = serial, ATMcriterion::String = "gradient")

    m = C.m
    Nx = C.Nx

    if verbose == true
        println("Optimizing component "*string(Nx)*":")
    end

    if typeof(optimkind) <: Nothing
        S = Storage(C.I.f, X)

        # Optimize coefficients
        if withqr == false
            coeff0 = getcoeff(C)

            if hessprecond == true
                precond = zeros(ncoeff(C), ncoeff(C))
                precond!(precond, coeff0, S, C, X)
                precond_chol = cholesky(Symmetric(precond); check = false)

                if issuccess(precond_chol) == true
                    res = Optim.optimize(Optim.only_fg!(negative_log_likelihood(S, C, X)), coeff0,
                          Optim.LBFGS(; m = 10, P = Preconditioner(Symmetric(precond), precond_chol)))
                elseif cond(Diagonal(precond)) < 10^6  #try the diagonal preconditioner
                    res = Optim.optimize(Optim.only_fg!(negative_log_likelihood(S, C, X)), coeff0,
                          Optim.LBFGS(; m = 10), P = Diagonal(precond))
                else # don't use any preconditioner
                    res = Optim.optimize(Optim.only_fg!(negative_log_likelihood(S, C, X)), coeff0,
                          Optim.LBFGS(; m = 10))
                end
            else
                res = Optim.optimize(Optim.only_fg!(negative_log_likelihood(S, C, X)), coeff0,
                      Optim.LBFGS(; m = 10))
            end

            setcoeff!(C, Optim.minimizer(res))
            error = res.minimum
        else
            F = QRscaling(S)
            coeff0 = getcoeff(C)
            mul!(coeff0, F.U, coeff0)

            # mul!(S.ψoffψd0, S.ψoffψd0, F.Uinv)
            # mul!(S.ψoffdψxd, S.ψoffdψxd, F.Uinv)
            if hessprecond == true
                qrprecond = zeros(ncoeff(C), ncoeff(C))
                qrprecond!(qrprecond, coeff0, F, S, C, X)
                qrprecond_chol = cholesky(Symmetric(qrprecond); check = false)

                if issuccess(qrprecond_chol) == true
                    res = Optim.optimize(Optim.only_fg!(qrnegative_log_likelihood(F, S, C, X)), coeff0,
                                         Optim.LBFGS(; m = 10, P = Preconditioner(Symmetric(qrprecond), qrprecond_chol)))
                elseif cond(Diagonal(qrprecond_chol)) < 10^6
                    res = Optim.optimize(Optim.only_fg!(qrnegative_log_likelihood(F, S, C, X)), coeff0,
                                         Optim.LBFGS(; m = 10, P = Diagonal(qrprecond)))
                else
                    res = Optim.optimize(Optim.only_fg!(qrnegative_log_likelihood(F, S, C, X)), coeff0,
                                         Optim.LBFGS(; m = 10))
                end
            else
                res = Optim.optimize(Optim.only_fg!(qrnegative_log_likelihood(F, S, C, X)), coeff0,
                                     Optim.LBFGS(; m = 10))
            end

            if Optim.converged(res)
                mul!(view(C.I.f.coeff,:), F.Uinv, Optim.minimizer(res))
            else
                error("Optimization hasn't converged")
            end


            error = res.minimum
        end

    elseif typeof(optimkind) <: Int64
        C, error =  greedyfit(m, Nx, X, optimkind;
                              α = C.α, withconstant = withconstant,
                              withqr = withqr, maxpatience = maxpatience,
                              verbose = verbose, hessprecond = hessprecond, b = getbasis(C), ATMcriterion = ATMcriterion)

    elseif optimkind ∈ ("kfold", "kfolds", "Kfold", "Kfolds")
        # Define cross-validation splits of data
        n_folds = 5
        folds = kfolds(1:size(X,2), k = n_folds)

        # Run greedy approximation
        max_iter = min(m-1, ceil(Int64, sqrt(size(X,2))), maxterms)

        valid_error = zeros(max_iter+1, n_folds)
        if typeof(P) <: Serial
            @inbounds for i=1:n_folds
                idx_train, idx_valid = folds[i]

                if verbose == true
                    println("Fold "*string(i)*" / "*string(n_folds)*":")
                end
                C, error = greedyfit(m, Nx, X[:,idx_train], X[:,idx_valid], max_iter;
                                     α = C.α, withconstant = withconstant, withqr = withqr, verbose  = verbose,
                                     hessprecond = hessprecond, b = getbasis(C), ATMcriterion = ATMcriterion)

                # error[2] contains the history of the validation error
                valid_error[:,i] .= deepcopy(error[2])
            end
        elseif typeof(P) <: Thread
            @inbounds  Threads.@threads for i=1:n_folds
                idx_train, idx_valid = folds[i]

                if verbose == true
                    println("Fold "*string(i)*":")
                end

                C, error = greedyfit(m, Nx, X[:,idx_train], X[:,idx_valid], max_iter;
                                     α = C.α, withconstant = withconstant, withqr = withqr, verbose  = verbose,
                                     hessprecond = hessprecond, b = getbasis(C), ATMcriterion = ATMcriterion)

                # error[2] contains the history of the validation error
                valid_error[:,i] .= deepcopy(error[2])
            end
        end

        # Find optimal numbers of terms
        mean_valid_error = mean(valid_error, dims  = 2)[:,1]

        _, opt_nterms = findmin(mean_valid_error)

        # Run greedy fit up to opt_nterms on all the data
        C, error = greedyfit(m, Nx, X, opt_nterms;
                             α = C.α, withqr = withqr, verbose  = verbose,
                             hessprecond = hessprecond, b = getbasis(C), ATMcriterion = ATMcriterion)

    elseif optimkind ∈ ("split", "Split")
        # 20% of the data is used for the cross-validation
        valid_train_split = 0.2
        nvalid = ceil(Int64, floor(valid_train_split*size(X,2)))
        X_train = X[:,nvalid+1:end]
        X_valid = X[:,1:nvalid]

        # Run greedy approximation
        max_iter =  min(m-1, maxterms, ceil(Int64, sqrt(size(X,2))))

        Cvalid, error = greedyfit(m, Nx, X_train, X_valid, max_iter;
                             α = C.α, withconstant = withconstant, withqr = withqr,
                             maxpatience = maxpatience, verbose  = verbose,
                             hessprecond = hessprecond, b = getbasis(C), ATMcriterion = ATMcriterion)

        # Find optimal numbers of terms
        train_error, valid_error = error
        _, opt_nterms = findmin(valid_error)

        # Since we add the features ina greedy fashion, we can simply pick the number of features that minimize the loss functino,
        # and optimize the coefficients with the entire data set

        # Run greedy fit up to opt_nterms on all the data
        C = HermiteMapComponent(Cvalid.m, Cvalid.Nx, getidx(Cvalid)[1:opt_nterms, :],
                                zeros(opt_nterms); α = Cvalid.α, b = getbasis(Cvalid))


        C, error = optimize(C, X, nothing;
                 maxterms = maxterms, withconstant = withconstant, withqr = withqr,
                 maxpatience = maxpatience, verbose = verbose, hessprecond = hessprecond,
                 P = P, ATMcriterion = ATMcriterion)
    else
        error("Argument max_terms is not recognized")
    end
    return C, error
end


function optimize(L::LinHermiteMapComponent, X::Array{Float64,2}, optimkind::Union{Nothing, Int64, String};
                  withconstant::Bool = false, withqr::Bool = false, maxpatience::Int64=20, verbose::Bool = false,
                  hessprecond::Bool = true, ATMcriterion::String="gradient")

    transform!(L.L, X)
    C = L.C
    C_opt, error = optimize(C, X, optimkind; α = C.α, withconstant = withconstant, withqr = withqr, maxpatience = maxpatience,
                            verbose = verbose, hessprecond = hessprecond, b = getbasis(C), ATMcriterion = ATMcriterion)

    itransform!(L.L, X)

    return LinHermiteMapComponent(L.L, C_opt), error
end
