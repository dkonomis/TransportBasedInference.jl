export lorenz96!, generate_lorenz96, spin_lorenz96, setup_lorenz96, benchmark_lorenz96, setup_order


"""
    lorenz96!(du,u,p,t)

Compute in-place the right-hand-side of the Lorenz-96 system for a state `u` at time `t`,
and store it in `du`. `p` is vector of user-defined parameters.
"""
function lorenz96!(du,u,p,t)
    F = 8.0
    n = size(u,1)
    du[1] = (u[2]-u[end-1])*u[end] - u[1] + F
    du[2] = (u[3]-u[end])*u[1] - u[2] + F
    du[end] = (u[1] - u[end-2])*u[end-1] - u[end] + F

    @inbounds for i=3:n-1
        du[i] = (u[i+1] - u[i-2])*u[i-1] - u[i] + F
    end
    return du
end


function generate_lorenz96(model::Model, x0::Array{Float64,1}, J::Int64)

    @assert model.Nx == size(x0,1) "Error dimension of the input"
    xt = zeros(model.Nx,J)
    x = deepcopy(x0)
    yt = zeros(model.Ny,J)
    tt = zeros(J)

    t0 = 0.0

    step = ceil(Int, model.Δtobs/model.Δtdyn)
    tspan = (t0, t0 + model.Δtobs)
    prob = ODEProblem(model.F.f,x,tspan)

    for i=1:J
    	# Run dynamics and save results
    	tspan = (t0 + (i-1)*model.Δtobs, t0 + i*model.Δtobs)
    	prob = remake(prob, tspan = tspan)

    	sol = solve(prob, Tsit5(), dt = model.Δtdyn, adaptive = false,
		            dense = false, save_everystep = false)
    	x .= deepcopy(sol.u[end])
    	# for j=1:step
    	# 	t = t0 + (i-1)*algo.Δtobs+(j-1)*algo.Δtdyn
        # 	_, x = model.f(t+(i-1)*model.Δtdyn, x)
    	# end
    	model.ϵx(x)

    	# Collect observations
    	tt[i] = deepcopy(i*model.Δtobs)
    	xt[:,i] = deepcopy(x)
		yt[:,i] = deepcopy(model.F.h(x, tt[i]))
		yt[:,i] .+= model.ϵy.m + model.ϵy.σ*randn(model.Ny)
    end
    	return SyntheticData(tt, x0, xt, yt)
end

function spin_lorenz96(model::Model, data::SyntheticData, Ne::Int64, path::String)
	@assert path[1]=='/' && path[end]=='/' "This function expects a / at the extremities of path"

	# Set initial condition
	X = zeros(model.Ny + model.Nx, Ne)
	X[model.Ny+1:model.Ny+model.Nx,:] .= rand(model.π0, Ne)#sqrt(model.C0)*randn(model.Nx, Ne) .+ model.m0

	J = model.Tspinup
	t0 = 0.0
	F = model.F
	enkf = StochEnKF(x->x, model.ϵy, model.Δtdyn, model.Δtobs, false, false)

	statehist = seqassim(F, data, J, model.ϵx, enkf, X, model.Ny, model.Nx, t0)

    save(path*"set_up_Ne"*string(Ne)*".jld", "state", statehist, "Ne", Ne, "x0", data.x0, "tt", data.tt, "xt", data.xt, "yt", data.yt)

    # return statehist
	_,_,rmse_mean,_ = metric_hist(rmse, data.xt[:,1:J], statehist[2:end])
	println("Ne "*string(Ne)* " RMSE: "*string(rmse_mean))
	# Save data
	save(path*"set_up_Ne"*string(Ne)*".jld", "X", statehist[end], "Ne", Ne, "x0", data.x0, "tt", data.tt, "xt", data.xt, "yt", data.yt)
end

function setup_lorenz96(path::String, Ne_array::Array{Int64,1})
    Nx = 40
    Ny = 20

    # The state is measured every fourth
    Δ = 2
    yidx = 1:Δ:Nx

    Δtdyn = 0.01
    Δtobs = 0.4

    σx = 1e-6#1e-2#1e-6#1e-2
    σy = sqrt(0.5)#1e-6#2.0

    ϵx = AdditiveInflation(Nx, zeros(Nx), σx)
    ϵy = AdditiveInflation(Ny, zeros(Ny), σy)
    tspinup = 200.0
    Tspinup = 2000
    tmetric = 400.0
    Tmetric = 4000
    t0 = 0.0
    tf = 600.0
    Tf = 6000

    Tburn = 2000
    Tstep = 4000
    Tspinup = 2000

    f = lorenz96!
    h(x, t) = x[yidx]
    # Create a local version of the observation operator
    h(x, idx, t) = x[idx]
	F = StateSpace(f, h)

    model = Model(Nx, Ny, Δtdyn, Δtobs, ϵx, ϵy, MvNormal(zeros(Nx), Matrix(1.0*I, Nx, Nx)), Tburn, Tstep, Tspinup, F);

    # Set initial condition
    x0 = model.m0 + sqrt(model.C0)*randn(Nx)
    # x0 = [0.645811242103507;  -1.465126216973632;   0.385227725149822];

    # Run dynamics and generate data
    data = generate_lorenz96(model, x0, model.Tspinup+model.Tstep);


    for Ne in Ne_array
        spin_lorenz96(model, data, Ne, path)
    end

    return model, data
end

function benchmark_lorenz96(model::Model, data::SyntheticData, path::String, Ne_array::Array{Int64,1},
	                        β_array::Array{Float64,1}, Lrad_array::Array{Float64,1})
@assert path[1]=='/' && path[end]=='/' "This function expects a / at the extremities of path"

#Store all the metric per number of ensemble members
metric_list = []

@showprogress for Ne in Ne_array
    metric_Ne = Metrics[]
    for β in β_array
		for Lrad in Lrad_array
		    @show Ne, β, Lrad
		    # Load file
		    X0 = load(path*"set_up_Ne"*string(Ne)*".jld", "X")

		    X = zeros(model.Ny + model.Nx, Ne)
		    X[model.Ny+1:model.Ny+model.Nx,:] .= copy(X0)
		    J = model.Tstep
		    t0 = model.Tspinup*model.Δtobs
		    F = model.F

			Δ = 2
			yidx = 1:Δ:model.Nx
			idx = vcat(collect(1:length(yidx))', collect(yidx)')

			enkf = SeqStochEnKF(x->x, F.h, β, model.ϵy, Ny, Nx, model.Δtdyn,
			                    idx, zeros(Nx+1, Ne), false, true)

		    # Use this multi-additive inflation
		    ϵx = MultiAddInflation(model.Nx, β, zeros(model.Nx), model.ϵx.Σ, model.ϵx.σ)

			# Create Localization structure
		    Gxy(i,j) = periodicmetric!(i,yidx[j], model.Nx)
		    Gyy(i,j) = periodicmetric!(yidx[i],yidx[j], model.Nx)
		    Loc = Localization(Lrad, Gxy, Gyy)

			@time statehist = seqassim(F, data, J, model.ϵx, enkf, X, model.Ny, model.Nx, t0, Loc);

		    metric = post_process(data, model, J, statehist)
		    push!(metric_Ne, deepcopy(metric))
			println("Ne "*string(Ne)*"& β "*string(β)*"& Lrad "*string(Lrad)*" RMSE: "*string(metric.rmse_mean))
		end
	end
	push!(metric_list, deepcopy(metric_Ne))
end

return metric_list
end


# Nx size of the state
# off_p contains the order for the off-diagonal component
# off_rad contains the radius for the localization of the map
# nonid_rad contains the number of non id components
# dist matrix of the distances between the variables
function setup_order(Nx, diagobs_p, diagunobs_p, off_p, off_rad, nonid_rad, dist::Array{Float64,2})

	dist = convert(Array{Int64,2}, dist)
    perm = sortperm(view(dist,:,1))

    dist_to_order = fill(-1, Nx)
    # fill!(view(dist_to_order,1:ceil(Int64,off_rad)), off_p)
    fill!(view(dist_to_order,1:ceil(Int64,min(off_rad, Nx))), off_p)
    order = [fill(-1,i) for i=1:Nx+1]
    nonid = Int64[]
    for i=1:Nx
        node_i = perm[i]
        dist_i1 = dist[1, node_i]

        # Vector to store order, offset of 1
        # because we have one scalar observation
        order_i = zeros(Int64, i-1)#view(order,i+1)
        if dist_i1 <= nonid_rad
            if i>1
            for j=1:i-1

                # extract distance to node i
                node_j = perm[j]
                dist_ij = dist[node_i, node_j]

                # compute order for variable based on distance
                order_i[j] = dist_to_order[dist_ij]
            end
            end
            # Define order for diagonal TM components and observation component
            if i==1 # observed mode
                order[2][2] = diagobs_p
                order[2][1] = off_p
            else # unobserved mode
                order[i+1][2:i] .= deepcopy(order_i)
                order[i+1][i+1] = diagunobs_p
                order[i+1][1] = -1
            end
        end
    end
    return order
end


#
# function benchmark_lorenz63(model::Model, data::SyntheticData, path::String, Ne_array::Array{Int64,1}, β_array::Array{Float64,1})
# @assert path[1]=='/' && path[end]=='/' "This function expects a / at the extremities of path"
#
# #Store all the metric per number of ensemble members
# Metric_hist = []
#
# @showprogress for Ne in Ne_array
#     Metric_Ne = Metrics[]
#     for β in β_array
#     @show Ne, β
#     # Load file
#     ens0 = load(path*"set_up_Ne"*string(Ne)*".jld", "ens")
#
#     ens = EnsembleStateMeas(3,3,Ne)
#     ens.state.S .= ens0
#     J = model.Tstep
#     t0 = model.Tspinup*model.Δtobs
#     dyn = DynamicalSystem(model.f, model.h)
#     enkf = StochEnKF(x->x, model.ϵy, model.Δtdyn, model.Δtobs, false, false)
#
#     # Use this multi-additive inflation
#     ϵx = MultiAddInflation(3, β, zeros(3), model.ϵx.Σ, model.ϵx.σ)
#
#     @time enshist = seqassim(dyn, data, J, ϵx, enkf, ens, t0)
#
#     Metric = post_process(data, model, J, enshist)
#     push!(Metric_Ne, deepcopy(Metric))
#     println("Ne "*string(Ne)*"& β "*string(β)*" RMSE: "*string(Metric.rmse_mean))
#     end
#     push!(Metric_hist, deepcopy(Metric_Ne))
# end
#
# return Metric_hist
# end
#
#
# function benchmark_TMap_lorenz63(model::Model, data::SyntheticData, path::String, Ne_array::Array{Int64,1}, β_array::Array{Float64,1})
# @assert path[1]=='/' && path[end]=='/' "This function expects a / at the extremities of path"
#
# #Store all the metric per number of ensemble members
# Metric_hist = []
#
# @showprogress for Ne in Ne_array
#     Metric_Ne = Metrics[]
#     for β in β_array
#     @show Ne, β
#     # Load file
#     ens0 = load(path*"set_up_Ne"*string(Ne)*".jld", "ens")
#
#     ens = EnsembleStateMeas(3,3,Ne)
#     ens.state.S .= ens0
#
#     J = model.Tstep
#     t0 = model.Tspinup*model.Δtobs
#     dyn = DynamicalSystem(model.f, model.h)
#     dist = metric_lorenz(3)
#     p = 0
#     # order = [[-1], [1; 1], [-1; 1; 0], [-1; 1; 1; 0]]
#     order = [[-1], [p; p], [-1; p; 0], [-1; p; p; 0]]
#     T = SparseTMap(3, 3, Ne, order, 2.0, 0.1, 1e-8, 10.0,  dist, dyn, x->x, β, model.ϵy, model.Δtdyn, model.Δtobs, false);
#
#     @time enshist = seqassim(dyn, data, J, model.ϵx, T, ens, t0)
#
#     Metric = post_process(data, model, J, enshist)
#     push!(Metric_Ne, deepcopy(Metric))
#     println("Ne "*string(Ne)*"& β "*string(β)*" RMSE: "*string(Metric.rmse_mean))
#     end
#     push!(Metric_hist, deepcopy(Metric_Ne))
# end
#
# return Metric_hist
# end
