
@testset "Validate loss function I" begin
    Nx = 1
    Ne = 10
    p = 3
    γ = 2.0

    ens = EnsembleState(Nx, Ne)
    ens.S .=     reshape([-1.5438
       -1.5518
        0.8671
       -0.1454
       -0.3862
        1.3162
       -0.7965
        0.1354
        0.4178
        0.8199],1,Ne)
    S = RadialMap(Nx, p; γ = γ);
    center_std(S, ens);

    W = create_weights(S, ens)
    weights(S, ens, W)

    ψ_off, ψ_mono, dψ_mono = rearrange_ricardo(W,Nx);
    μψ = deepcopy(mean(ψ_mono, dims=2))
    σψ = deepcopy(std(ψ_mono, dims=2, corrected=false))

    ψ_mono .-= μψ
    ψ_mono ./= σψ
    dψ_mono ./= σψ

    A = ψ_mono*ψ_mono'

# Value for this example from Ricardo Baptista's code
#     A = [1.000000000000000   0.980746250237442   0.949585186065365   0.874893160310884   0.682688353791794
#    0.980746250237442   1.000000000000000   0.992392810306380   0.951686939442048   0.794587369107029
#    0.949585186065365   0.992392810306380   1.000000000000000   0.979987807512526   0.841920530108716
#    0.874893160310884   0.951686939442048   0.979987807512526   1.000000000000000   0.924572967646111
#    0.682688353791794   0.794587369107029   0.841920530108716   0.924572967646111   1.000000000000000]
#
#    dψ = [1.943027194236598   0.904099317171178   0.363590761264482   0.103708119866970   0.003658358886509
#    1.949127329018457   0.900154645724251   0.358540918818191   0.101474664830914   0.003524731655464
#    0.436105078812650   0.785902678977702   0.903915317182112   1.478321127032274   2.769938074690495
#    0.940754438483933   1.187522900065327   1.375388815415954   1.249642233914406   0.493692853837867
#    1.094596689101933   1.214822387670764   1.280911634416390   0.981040834765123   0.264471303061320
#    0.288722974980864   0.555375334050147   0.517307925073611   1.026368388570445   4.005813485764689
#    1.380134162445589   1.181212729079411   0.975263367972602   0.543176897811297   0.074249159004658
#    0.776788122078680   1.114885036778955   1.375388815415954   1.502313102175688   0.916745911337340
#    0.630159061208850   1.005528754335045   1.256866405570924   1.625364312645948   1.525991525022805
#    0.454238308718550   0.810349920313954   0.945882762308085   1.512212666353956   2.631844256908664]
    nb = size(ψ_mono,1)
    rmul!(A,1/Ne)
    λ = 0.0
    δ = 0.0;

    x0 = ones(nb);

    Lhd = LHD(A, Matrix(dψ_mono'), λ, δ)
    Lhd(x0,true)

    @test norm(Lhd.J[1] - 9.858183469194048)<1e-10
    @test norm(Lhd.G - [4.254136703227439;4.518792556597960;4.583786234498148;4.551417068663062;4.037990186069983])<1e-10
    @test norm(Lhd.H - [1.092420543831142   1.038440852206475   0.988737431456852   0.902158085870462   0.699932284218600;
   1.038440852206475   1.044839328780384   1.030133800308906   0.984518683331781   0.822101516960292;
   0.988737431456852   1.030133800308906   1.036827933644060   1.015461469462408   0.872825798615600;
   0.902158085870462   0.984518683331781   1.015461469462408   1.039520711149700   0.969205731345725;
   0.699932284218600   0.822101516960292   0.872825798615600   0.969205731345725   1.085482924097099])<1e-10

   J = Lhd(x0,false;noutput =1)
   @test norm(J[1] - 9.858183469194048)<1e-10

   J, G = Lhd(x0,false;noutput =2)
   @test norm(J[1] - 9.858183469194048)<1e-10
   @test norm(G - [4.254136703227439;4.518792556597960;4.583786234498148;4.551417068663062;4.037990186069983])<1e-10

   J, G, H = Lhd(x0,false;noutput =3)
   @test norm(J[1] - 9.858183469194048)<1e-10
   @test norm(G - [4.254136703227439;4.518792556597960;4.583786234498148;4.551417068663062;4.037990186069983])<1e-10
   @test norm(H - [1.092420543831142   1.038440852206475   0.988737431456852   0.902158085870462   0.699932284218600;
  1.038440852206475   1.044839328780384   1.030133800308906   0.984518683331781   0.822101516960292;
  0.988737431456852   1.030133800308906   1.036827933644060   1.015461469462408   0.872825798615600;
  0.902158085870462   0.984518683331781   1.015461469462408   1.039520711149700   0.969205731345725;
  0.699932284218600   0.822101516960292   0.872825798615600   0.969205731345725   1.085482924097099])<1e-10

end

@testset "Validate loss function II " begin
    Nx = 1
    Ne = 10
    p = 3
    γ = 2.0

    ens = EnsembleState(Nx, Ne)
    ens.S .=     reshape([-1.5438
       -1.5518
        0.8671
       -0.1454
       -0.3862
        1.3162
       -0.7965
        0.1354
        0.4178
        0.8199],1,Ne)
    S = RadialMap(Nx, p; γ = γ);
    center_std(S, ens);

    W = create_weights(S, ens)
    weights(S, ens, W)

    ψ_off, ψ_mono, dψ_mono = rearrange_ricardo(W,Nx);
    μψ = deepcopy(mean(ψ_mono, dims=2))
    σψ = deepcopy(std(ψ_mono, dims=2, corrected=false))

    ψ_mono .-= μψ
    ψ_mono ./= σψ
    dψ_mono ./= σψ

    A = ψ_mono*ψ_mono'
    nb = size(ψ_mono,1)
    rmul!(A,1/Ne)
    λ = 0.1
    δ = 1e-5;

    x0 = ones(nb);

    Lhd = LHD(A, Matrix(dψ_mono'), λ, δ)
    Lhd(x0,true)

    @test norm(Lhd.J[1] - 9.883403430471539)<1e-10
    @test norm(Lhd.G - [4.264184020096037; 4.528841856919714; 4.593835774344472; 4.561466277291902; 4.048034781531958])<1e-10
    @test norm(Lhd.H - [1.102418695447991   1.038439698331744   0.988736648423690   0.902157540580130   0.699931939345165;
   1.038439698331744   1.054838432007260   1.030133045500428   0.984518026706753   0.822100966685589;
   0.988736648423690   1.030133045500428   1.046827197096436   1.015460759999810   0.872825180519502;
   0.902157540580130   0.984518026706753   1.015460759999810   1.049519920747334   0.969204838703841;
   0.699931939345165   0.822100966685589   0.872825180519502   0.969204838703841   1.095481214464262])<1e-10

   J = Lhd(x0,false;noutput =1)
   @test norm(J[1] - 9.883403430471539)<1e-10

   J, G = Lhd(x0,false;noutput =2)
   @test norm(J[1] - 9.883403430471539)<1e-10
   @test norm(G - [4.264184020096037; 4.528841856919714; 4.593835774344472; 4.561466277291902; 4.048034781531958])<1e-10

   J, G, H = Lhd(x0,false;noutput =3)
   @test norm(J[1] - 9.883403430471539)<1e-10
   @test norm(G - [4.264184020096037; 4.528841856919714; 4.593835774344472; 4.561466277291902; 4.048034781531958])<1e-10
   @test norm(H - [1.102418695447991   1.038439698331744   0.988736648423690   0.902157540580130   0.699931939345165;
  1.038439698331744   1.054838432007260   1.030133045500428   0.984518026706753   0.822100966685589;
  0.988736648423690   1.030133045500428   1.046827197096436   1.015460759999810   0.872825180519502;
  0.902157540580130   0.984518026706753   1.015460759999810   1.049519920747334   0.969204838703841;
  0.699931939345165   0.822100966685589   0.872825180519502   0.969204838703841   1.095481214464262])<1e-10
end
