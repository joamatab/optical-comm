function ber = ber_apd_montecarlo(mpam, tx, fiber, apd, rx, sim)

% Channel response
Ptx = design_filter('matched', mpam.pshape, 1/sim.Mct); % transmitted pulse shape

% Hch does not include receiver filter
if isfield(tx, 'modulator')
    Hch = Ptx.H(sim.f/sim.fs).*tx.modulator.H(sim.f).*exp(1j*2*pi*sim.f*tx.modulator.grpdelay)...
    .*fiber.H(sim.f, tx).*apd.H(sim.f);
else
    Hch = Ptx.H(sim.f/sim.fs).*fiber.H(sim.f, tx).*apd.H(sim.f);
end

link_gain = apd.Gain*apd.R*fiber.link_attenuation(tx.lamb); % Overall link gain

% Ajust levels to desired transmitted power and extinction ratio
mpam = mpam.adjust_levels(tx.Ptx, tx.rexdB);
Pmax = mpam.a(end); % used in the automatic gain control stage

% Modulated PAM signal
dataTX = randi([0 mpam.M-1], 1, sim.Nsymb); % Random sequence
xt = mpam.mod(dataTX, sim.Mct);
xt(1:sim.Mct*sim.Ndiscard) = 0; % zero sim.Ndiscard first symbols
xt(end-sim.Mct*sim.Ndiscard+1:end) = 0; % zero sim.Ndiscard last symbbols

% Generate optical signal
[Et, ~] = optical_modulator(xt, tx, sim);

% Fiber propagation
[~, Pt] = fiber.linear_propagation(Et, sim.f, tx.lamb);

%% Detect and add noises
yt = apd.detect(Pt, sim.fs, 'gaussian', rx.N0);

% Automatic gain control
% Pmax = 2*tx.Ptx/(1 + 10^(-abs(tx.rexdB)/10)); % calculated from mpam.a
yt = yt/(Pmax*link_gain); % just refer power values back to transmitter
mpam = mpam.norm_levels;

%% Equalization
if isfield(rx, 'eq') && (isfield(tx, 'modulator') || ~isinf(apd.BW))
    rx.eq.TrainSeq = dataTX;
else % otherwise only filter using rx.elefilt
    rx.eq.type = 'None';
end
   
% Equalize
[yd, rx.eq] = equalize(rx.eq, yt, Hch, mpam, rx, sim);
   
% Symbols to be discarded in BER calculation
Ndiscard = sim.Ndiscard*[1 1];
if isfield(rx.eq, 'Ntrain')
    Ndiscard(1) = Ndiscard(1) + rx.eq.Ntrain;
end
if isfield(rx.eq, 'Ntaps')
    Ndiscard = Ndiscard + rx.eq.Ntaps;
end
ndiscard = [1:Ndiscard(1) sim.Nsymb-Ndiscard(2):sim.Nsymb];
yd(ndiscard) = []; 
dataTX(ndiscard) = [];

% Demodulate
dataRX = mpam.demod(yd);

% True BER
[~, ber] = biterr(dataRX, dataTX);

if sim.verbose
    % Signal
    figure(102), hold on
    plot(link_gain*Pt)
    plot(yt, '-k')
    plot(ix, yd, 'o')
    legend('Transmitted power', 'Received signal', 'Samples')
    
    % Heuristic pdf for a level
    figure(100)
    [nn, xx] = hist(yd(dataTX == 2), 50);
    nn = nn/trapz(xx, nn);
    bar(xx, nn)
end    
