function [SA_out, CT_out] = gsw_stabilise_SA_CT(SA_in,CT_in,p,opt_1,opt_2)

% gsw_stabilise_SA_CT              minimally adjusts both Absolute Salinity
%                                   and Conservative Temperature to produce
%                                  a stable water column (75-term equation)
%==========================================================================
%
% USAGE:
%  [SA_out, CT_out] = gsw_stabilise_SA_CT(SA_in,CT_in,p,{opt_1,opt_2})
%
% DESCRIPTION:
%  This function stabilises a water column, this is achieved by minimally
%  adjusting both the Absolute Salinity SA and Conservative Temperature CT
%  values such that the minimum stability is adjusted to be atleast
%  1/5th of the square of earth's rotation rate.
%
%  This programme requires either the Optimization toolbox or Tomlab CPLEX.
%  If there are a up to several hundred data points in the cast then
%  Matlab's Optimization toolbox produces reasonable results, but if there
%  are thousands of bottles in the cast or the best possible output is
%  wanted then the CPLEX solver is required. This programme will determine
%  if Tomlab or the Optimization toolbox is available to the user, if both
%  are available it will use Tomlab.
%
%  Note that this 75-term equation has been fitted in a restricted range of
%  parameter space, and is most accurate inside the "oceanographic funnel"
%  described in McDougall et al. (2003).  The GSW library function
%  "gsw_infunnel(SA,CT,p)" is avaialble to be used if one wants to test if
%  some of one's data lies outside this "funnel".
%
% INPUT:
%  SA_in  =  uncorrected Absolute Salinity                         [ g/kg ]
%  CT_in  =  uncorrected Conservative Temperature (ITS-90)        [ deg C ]
%  p      =  sea pressure                                          [ dbar ]
%         ( i.e. absolute pressure - 10.1325 dbar )
%
% OPTIONAL:
%  opt_1 = Nsquared lower limit                                   [ 1/s^2 ]
%  Note. If Nsquared_lowerlimit is not supplied, a default minimum 
%   stability of 1 x 10^-9 s^-2 will be applied.
%  or,
%  opt_1 =  longitude in decimal degrees                     [ 0 ... +360 ]
%                                                     or  [ -180 ... +180 ]
%  opt_2 =  latitude in decimal degrees north               [ -90 ... +90 ]
%
%  SA_in & CT_in need to have the same dimensions.
%  p may have dimensions 1x1 or Mx1 or 1xN or MxN, where SA_in & CT_in are
%  MxN.
%  opt_1 equal to Nsquared_lowerlimit, if provided, may have dimensions 1x1
%  or (M-1)x1 or 1xN or (M-1)xN, where SA_in & CT_in are MxN.
%  opt_1 equal to long & opt_2 equal to lat, if provided, may have
%  dimensions 1x1 or (M-1)x1 or 1xN or (M-1)xN, where SA_in & CT_in are
%  MxN.
%
% OUTPUT:
%  SA_out  =  corrected stablised Absolute Salinity                [ g/kg ]
%  CT_out  =  corrected stablised Conservative Temperature        [ deg C ]
%
% AUTHOR:
%  Paul Barker and Trevor McDougall                    [ help@teos-10.org ]
%
% VERSION NUMBER: 3.05.5 (30th June, 2016)
%
% REFERENCES:
%  Barker, P.M., and T.J. McDougall, 2016: Stabilisation of hydrographic 
%    profiles.  J. Atmosph. Ocean. Tech., submitted.
%
%  IOC, SCOR and IAPSO, 2010: The international thermodynamic equation of
%   seawater - 2010: Calculation and use of thermodynamic properties.
%   Intergovernmental Oceanographic Commission, Manuals and Guides No. 56,
%   UNESCO (English), 196 pp.  Available from http://www.TEOS-10.org
%
%  McDougall, T.J., D.R. Jackett, D.G. Wright and R. Feistel, 2003:
%   Accurate and computationally efficient algorithms for potential
%   temperature and density of seawater.  J. Atmosph. Ocean. Tech., 20,
%   pp. 730-741.
%
%  Roquet, F., G. Madec, T.J. McDougall, P.M. Barker, 2015: Accurate
%   polynomial expressions for the density and specifc volume of seawater
%   using the TEOS-10 standard. Ocean Modelling, 90, pp. 29-43.
%
%  The software is available from http://www.TEOS-10.org
%
%  The Tomlab software is available from http://www.tomopt.com
%
%==========================================================================

%--------------------------------------------------------------------------
% Check if necessary software exists
%--------------------------------------------------------------------------

if exist('tomlabVersion') == 2
    [TomV,os,TV] = tomlabVersion;
    if TV(9)
        software_solver = 1; 
    else
        fprintf('gsw_stabilise_SA_CT: No valid license for the CPLEX solver\n');
        if license('checkout', 'Optimization_Toolbox')
            software_solver = 2; 
        else
            error('gsw_stabilise_SA_CT: No valid license for Tomlab or MATLAB-Optimization')
        end
    end
elseif license('checkout', 'Optimization_Toolbox')
    software_solver = 2; 
else
    error('gsw_stabilise_SA_CT: No valid license for Tomlab or MATLAB-Optimization')
end

%--------------------------------------------------------------------------
% Check variables and resize if necessary
%--------------------------------------------------------------------------

if ~(nargin == 3 | nargin == 4 | nargin == 5)
    error('gsw_stabilise_SA_CT:  Requires three or four or five inputs')
end

if ~(nargout == 2)
    error('gsw_stabilise_SA_CT:  Requires two outputs')
end

[ms,ns] = size(SA_in);
[mt,nt] = size(CT_in);
[mp,np] = size(p);

if (mt ~= ms | nt ~= ns)
    error('gsw_stabilise_SA_CT: SA_in and CT_in must have same dimensions')
end

if (mp == 1) & (np == 1)
    error('gsw_stabilise_SA_CT:  There must be at least 3 bottles')
elseif (ns == np) & (mp == 1)
    p = p(ones(1,ms), :);
elseif (ms == mp) & (np == 1)
    p = p(:,ones(1,ns));
elseif (ns == mp) & (np == 1)
    p = p.'; 
    p = p(ones(1,ms), :);
elseif (ms == np) & (mp == 1)
     p = p.';  
     p = p(:,ones(1,ns));
elseif (ms == np) & (ns == mp)
     p = p.';   
elseif (ms == mp) & (ns == np)
    % ok
else
    error('gsw_stabilise_SA_CT: Inputs array dimensions arguments do not agree')
end 

if ms == 1
    SA_in = SA_in.';
    CT_in = CT_in.';
    p = p.';
    transposed = 1;
else
    transposed = 0;
end

[mp,number_profiles] = size(p);

if nargin == 4
    Nsquared_lowerlimit = opt_1;
    if transposed
        Nsquared_lowerlimit = Nsquared_lowerlimit.';
    end
    [mN2,nN2] = size(Nsquared_lowerlimit);
    if (mN2 == 1) & (nN2 == 1)
        Nsquared_lowerlimit_tmp = Nsquared_lowerlimit*ones(mp,number_profiles);
    elseif (number_profiles == nN2) & (mN2 == 1)
        Nsquared_lowerlimit_tmp = Nsquared_lowerlimit(ones(1,mp),:);
    elseif (mp == mN2) & (number_profiles == nN2)
        Nsquared_lowerlimit_tmp = Nsquared_lowerlimit;   
    elseif (mp == (mN2+1)) & (nN2 == 1)
        Nsquared_lowerlimit_tmp = NaN(mp,number_profiles);
        Nsquared_lowerlimit_tmp(2:end,:) = Nsquared_lowerlimit(:,ones(1,number_profiles));
    elseif (mp == (mN2+1)) & (number_profiles == nN2)
        Nsquared_lowerlimit_tmp = NaN(mp,number_profiles);
        Nsquared_lowerlimit_tmp(2:end,:) = Nsquared_lowerlimit;
    else
        error('gsw_stabilise_SA_CT: Inputs array dimensions arguments do not agree')
    end
end

if nargin == 5
    long = opt_1;
    lat = opt_2;
    
    [mlo,nlo] = size(long);
    long(long < 0) = long(long < 0) + 360;
    
    if (mlo == 1) & (nlo == 1)
        long = long*ones(mp,number_profiles);
    elseif (number_profiles == nlo) & (mlo == 1)
        long = long(ones(1,mp),:);
    elseif (mp == mlo) & (nlo == 1)
        long = long(:,ones(1,number_profiles));
    elseif (number_profiles == mlo) & (nlo == 1)
        long = long.';
        long = long(ones(1,mp),:);
    elseif (mp == nlo) & (mlo == 1)
        long = long.';
        long = long(:,ones(1,number_profiles));
    elseif (mp == mlo) & (number_profiles == nlo)
        % ok
    else
        error('gsw_stabilise_SA_CT: Inputs array dimensions arguments do not agree')
    end
    
    [mla,nla] = size(lat);
    
    if (mla == 1) & (nla == 1)
        lat = lat*ones(mp,number_profiles);
    elseif (number_profiles == nla) & (mla == 1)
        lat = lat(ones(1,mp), :);
    elseif (mp == mla) & (nla == 1)
        lat = lat(:,ones(1,number_profiles));
    elseif (number_profiles == mla) & (nla == 1)
        lat = lat.';
        lat = lat(ones(1,mp), :);
    elseif (mp == mla) & (number_profiles == nla)
        % ok
    else
        error('gsw_stabilise_SA_CT: Inputs array dimensions arguments do not agree')
    end
    
    Nsquared_lowerlimit_tmp = gsw_Nsquared_lowerlimit(p,long,lat);
    
    clear long mla nla lat mlo mlo
end

%--------------------------------------------------------------------------
% Start of the calculation
%--------------------------------------------------------------------------

Nsquared_lowerlimit_default = 1e-9;

% db2Pa = 1e4;
% grav = 9.7963 (Griffies, 2004)
c =1.250423402612047e+02; % c = 1.2*db2Pa./(grav.^2);

SA_out = NaN(mp,number_profiles);
CT_out = SA_out;

for Iprofile = 1:number_profiles
        
    [Inn] = find(~isnan(SA_in(:,Iprofile) + CT_in(:,Iprofile) + p(:,Iprofile)));
    
    if length(Inn) < 2
        SA_out(Inn,Iprofile) = SA_in(Inn,Iprofile);
        CT_out(Inn,Iprofile) = CT_in(Inn,Iprofile);
        
    else
        SA_tmp = SA_in(Inn,Iprofile);
        CT_tmp = CT_in(Inn,Iprofile);
        p_tmp = p(Inn,Iprofile);
        
        mean_SA_in = mean(SA_tmp);
        mean_CT_in = mean(CT_tmp);
        
        pl = length(p_tmp);
        
        % Calculate Nsquared of the cast
        [N2_tmp,N2_p_tmp,N2_specvol_tmp,N2_alpha_tmp,N2_beta_tmp, dSA_tmp, dCT_tmp, dp_tmp] = ...
            gsw_Nsquared_min(SA_tmp,CT_tmp,p_tmp);
        
        %--------------------------------------------------------------------------
        % Set the Nsquared lower limit
        %--------------------------------------------------------------------------
        if ~exist('Nsquared_lowerlimit_tmp','var')
            Nsquared_lowerlimit = Nsquared_lowerlimit_default*ones(pl-1,1); %default
        else
            dummy = squeeze(Nsquared_lowerlimit_tmp(Inn,Iprofile));
            Nsquared_lowerlimit = dummy(2:end);
        end
        %--------------------------------------------------------------------------

        % Determine if any of the bottle pairs have stabilities less than
        % the Nsquared lower limit
        if any(N2_tmp - Nsquared_lowerlimit < 0)
            
            %--------------------------------------------------------------------------
            % Initial stabilisation.
            % Make the cast neutrally stable and calculate the mixed layer pressure.
            % Adjust SA and CT such that the cast has stabilities greater than
            % 1 x 10^-9 s^-2. This is about 1/5th of (2 x omega)^2. Note this 
            % stabilised cast has no contraints to the direction of the SA-CT changes. 
            %--------------------------------------------------------------------------
            [Iunstable] = find((N2_tmp - (Nsquared_lowerlimit_default.*ones(pl-1,1))) < 0);
            if any(Iunstable)
                [SA_neutral, CT_neutral] = gsw_stabilise_unconstrained_SA_CT(SA_tmp,CT_tmp,p_tmp,Nsquared_lowerlimit_default,software_solver);
                [Inan_neutral] = find(isnan(SA_neutral + CT_neutral));
                [Inn_neutral] = find(~isnan(SA_neutral + CT_neutral));
                if ~isempty(Inan_neutral) & length(Inn_neutral) > 1
                    [Inn_neutral] = find(~isnan(SA_neutral + CT_neutral));
                    [SA_neutral, CT_neutral] = gsw_linear_interp_SA_CT(SA_neutral(Inn_neutral), CT_neutral(Inn_neutral),p_tmp(Inn_neutral),p_tmp);
                    SA_neutral = SA_neutral(:);
                    CT_neutral = CT_neutral(:);
                elseif length(Inn_neutral) < 2
                    continue
                end
                mlp = gsw_mlp(SA_neutral,CT_neutral,p_tmp);
            else
                SA_neutral = SA_tmp;
                CT_neutral = CT_tmp;
                mlp = gsw_mlp(SA_neutral,CT_neutral,p_tmp);
            end
            
            mlp(isnan(mlp)) = min(p_tmp);
                        
            % Find the index of the bottle that is just deeper than the mlp.
            diff_p_mlp = p_tmp - mlp;
            deeper_diff_p_mlp = diff_p_mlp(diff_p_mlp >= 0);
            closest_p = min(deeper_diff_p_mlp);
            Imlp = find(diff_p_mlp == closest_p);
            
            % Calculate and intergrate d_rho_local for bottles that are 
            % deeper than the mlp.
            Ishallow_mlp = [Imlp:pl-1];
            Ideep_mlp = [Imlp+1:pl];
            if (pl - Imlp) <=1
                Ishallow_mlp = [1:pl-1];
                Ideep_mlp = [2:pl];
            end
            p_mid = 0.5*(p_tmp(Ishallow_mlp) + p_tmp(Ideep_mlp));
            rho_local_shallow = gsw_rho(SA_neutral(Ishallow_mlp),CT_neutral(Ishallow_mlp),p_mid);
            rho_local_deep = gsw_rho(SA_neutral(Ideep_mlp),CT_neutral(Ideep_mlp),p_mid);
            d_rho_local = rho_local_deep - rho_local_shallow;
            intergral_rho_local = sum(d_rho_local);
            
            if intergral_rho_local < 0.1 | (pl - Imlp) < 3
                % very small denstiy range, output SA and CT adjusted with
                % no constraint profile or there are only 2 bottles located below the
                % mixed layer.
                SA_out(Inn,Iprofile) = SA_neutral;
                CT_out(Inn,Iprofile) = CT_neutral;
                
            else
                % Calculate N, the number of bottles needed such that drho_local
                % is not < 0.1
                N = 40;
                while (intergral_rho_local/N < 0.1)
                    N = N - 1;
                end
                if N < 3
                    N = 3;
                end
                
                Name = 'stabilise the water column, adjusting SA and CT with constraints';
                
                Number_of_iterations = 0;
                unstable = 0;
                set_bounds = 1;
                
                while unstable < 1
                    
                    Number_of_iterations = Number_of_iterations + 1;
                    
                    %-------------------------------------------------------------
                    % Constraints from a smoothed, coarse resolution SA-CT profile
                    % There is the option to return either the arctangent of the 
                    % angle of the bounds of the individual bottles or the bounds 
                    % of the indivdual bottles.
                    %-------------------------------------------------------------
                                                         
%                     SA_CT_angle_bottle = gsw_stabilsation_constraints(SA_neutral,CT_neutral,p_tmp,Nsquared_lowerlimit,pl,Imlp,N);
%                     dSA_bottle = cos(SA_CT_angle_bottle);
%                     dCT_bottle = sin(SA_CT_angle_bottle);
                    
                    [dSA_bottle, dCT_bottle] = ...
                        gsw_stabilsation_constraints(SA_neutral,CT_neutral,p_tmp,Nsquared_lowerlimit,pl,Imlp,N,software_solver);
                   
                    %----------------------------------------------------------
                    % Stabilisation
                    %----------------------------------------------------------
                    
                    alpha_beta = N2_alpha_tmp./N2_beta_tmp;
                                                           
                    b_U = N2_beta_tmp.*dSA_tmp - N2_alpha_tmp.*dCT_tmp ...
                                  - c*Nsquared_lowerlimit.*dp_tmp.*N2_specvol_tmp;
                    % Note that c = 1.2*db2Pa./(grav.^2);

                    %--------------------------------------------------------------------------
                    % The solver
                    %--------------------------------------------------------------------------
                    switch software_solver
                    %--------------------------------------------------------------------------
                        
                        case 1 % Tomlab CPLEX solver
                            
                            if set_bounds == 1
                                pl_pair = pl-1;
                                two_pl = 2*pl;
                                H_dummy = ones(two_pl,1);
                                
                                A_s = pl_pair + pl;
                                A_i = 2*A_s + 1;
                                A_e =  A_i*(pl_pair-1) + pl;
                                A = zeros(A_s,two_pl);
                                % change the last row for conservation of either property
                                %  A(pl_pair+pl,2:2:two_pl) = ones(1,pl);      % conserve CT
                                %  A(pl_pair+pl,1:2:two_pl-1) = ones(1,pl);    % conserve SA
                                
                                f = zeros(two_pl,1);                               
                                b_L = -inf*ones(pl-1,1);
                                b_L(pl:two_pl-1,1) = zeros(pl,1);
                                x_L = -inf*ones(two_pl,1);
                                x_U = inf*ones(two_pl,1);
                                x_0 = zeros(two_pl,1);                                
                                set_bounds = 0;
                            end
                            
                            H_dummy(2:2:(two_pl-2)) = alpha_beta.*alpha_beta;
                            H = sparse(1:two_pl,1:two_pl, H_dummy);
                             
                            A([1:A_i:A_e]) = N2_beta_tmp;
                            A([A_s+1:A_i:(A_e+A_s+1)]) = -N2_alpha_tmp;
                            A([2*A_s+1:A_i:(A_e+2*A_s+1)]) = -N2_beta_tmp;
                            A([3*A_s+1:A_i:(A_e+3*A_s+1)]) = N2_alpha_tmp;                                                      
                            A([pl:A_i:(pl+((pl-1)*A_i))]) = dCT_bottle;
                            A([(pl+A_s):A_i:(pl+A_s+((pl-1)*A_i))]) = -dSA_bottle;
                            
                            b_U(pl:two_pl-1,1) = zeros(pl,1);
                            x_L(1:2:two_pl-1) = -SA_tmp;
                            
                            Prob = qpAssign(H, f, A, b_L, b_U, x_L, x_U, x_0, Name,[], [], [], [], []);
                            Result = tomRun('cplex', Prob, 0);
                            
                            SA_tmp = SA_tmp + Result.x_k(1:2:two_pl-1);
                            CT_tmp = CT_tmp + Result.x_k(2:2:two_pl);
                            
                    %--------------------------------------------------------------------------
                            
                        case 2 % Matlab solver
                            if set_bounds == 1
                                pl_pair = pl-1;
                                two_pl = 2*pl;
                                H = eye(two_pl);
                                A_s = pl_pair;
                                A_i = 2*A_s + 1;
                                A_e = A_i*(pl_pair-1);
                                A = zeros(pl_pair,two_pl);
                                Aeq = zeros(pl_pair+1,two_pl);
                                beq = zeros(pl,1);
                                f = zeros(two_pl,1);                               
                                x_L = -inf*ones(two_pl,1);
                                x_U = inf*ones(two_pl,1);
                                x_0 = zeros(two_pl,1);
                                set_bounds = 0;
                            end
                            
                            H([(two_pl+2):2*(two_pl+1):(4*pl*(pl-1)-2)]) = alpha_beta.*alpha_beta;
                            
                            A([1:A_i:(A_e+1)]) = N2_beta_tmp;
                            A([A_s+1:A_i:(A_e+A_s+1)]) = -N2_alpha_tmp;
                            A([2*A_s+1:A_i:(A_e+2*A_s+1)]) = -N2_beta_tmp;
                            A([3*A_s+1:A_i:(A_e+3*A_s+1)]) = N2_alpha_tmp;
                                                    
                            Aeq([1:A_i+2:(pl*A_i)]) = dCT_bottle;
                            Aeq([(pl+1):A_i+2:(pl+pl*A_i)]) = -dSA_bottle;
                            
                            x_L(1:2:two_pl-1) = -SA_tmp;
                            
                            if Number_of_iterations == 1
                                opts = optimset('Algorithm','active-set','Display','off');
                            end
                            x = quadprog(H, f, A, b_U, Aeq, beq, x_L, x_U, x_0, opts);
                            
                            SA_tmp = SA_tmp + x(1:2:two_pl-1);
                            CT_tmp = CT_tmp + x(2:2:two_pl);
                            
                    %--------------------------------------------------------------------------
                    end
                    %--------------------------------------------------------------------------
                    
                    %--------------------------------------------------------------------------
                    % Set limits and interpolate variables of any bottles
                    % ouside of the limits
                    %--------------------------------------------------------------------------
                    if abs(nanmean(CT_tmp) - mean_CT_in) < 10 & ...
                            abs(nanmean(SA_tmp) - mean_SA_in) < (10*mean(alpha_beta))
                        
                        CT_tmp(p_tmp < 100 & (CT_tmp > 80 | CT_tmp < -12)) = NaN;
                        CT_tmp(p_tmp >= 100 & (CT_tmp > 40 | CT_tmp < -12)) = NaN;
                        CT_tmp(SA_tmp > 120 | p_tmp > 12000) = NaN;
                        
                        if any(isnan(CT_tmp))
                            [Inan] = find(isnan(SA_tmp + CT_tmp));
                            [Inn2] = find(~isnan(SA_tmp + CT_tmp));
                            if ~isempty(Inn2)
                                [SA_tmp(Inan),CT_tmp(Inan)] = gsw_rr68_interp_SA_CT(SA_tmp(Inn2),CT_tmp(Inn2),p_tmp(Inn2),p_tmp(Inan));
                                if any(isnan(SA_tmp + CT_tmp))
                                    [Inan] = find(isnan(SA_tmp + CT_tmp));
                                    [Inn2] = find(~isnan(SA_tmp + CT_tmp ));
                                    [SA_tmp(Inan),CT_tmp(Inan)] = gsw_linear_interp_SA_CT(SA_tmp(Inn2),CT_tmp(Inn2),p_tmp(Inn2),p_tmp(Inan));
                                end
                                
                                [SA_neutral, CT_neutral] = gsw_stabilise_unconstrained_SA_CT(SA_tmp,CT_tmp,p_tmp,Nsquared_lowerlimit_default,software_solver);
                                [Inan_neutral] = find(isnan(SA_neutral + CT_neutral));
                                if ~isempty(Inan_neutral)
                                    [Inn_neutral] = find(~isnan(SA_neutral + CT_neutral));
                                    [SA_neutral, CT_neutral] = gsw_linear_interp_SA_CT(SA_neutral(Inn_neutral), CT_neutral(Inn_neutral),p_tmp(Inn_neutral),p_tmp);
                                    SA_neutral = SA_neutral(:);
                                    CT_neutral = CT_neutral(:);
                                end
                                set_bounds = 1; %This may not be needed.
                            else
                                [Inn] = find(~isnan(SA_in(:,Iprofile) + CT_in(:,Iprofile) + p(:,Iprofile)));
                                [SA_tmp, CT_tmp] = gsw_stabilise_unconstrained_SA_CT(SA_in(Inn,Iprofile),CT_in(Inn,Iprofile),p(Inn,Iprofile),Nsquared_lowerlimit_default,software_solver);
                                unstable = 1;
                                if isempty(SA_tmp) | isempty(CT_tmp)
                                    continue
                                end
                            end
                        end
                    else
                        [Inn] = find(~isnan(SA_in(:,Iprofile) + CT_in(:,Iprofile) + p(:,Iprofile)));
                        [SA_tmp, CT_tmp] = gsw_stabilise_unconstrained_SA_CT(SA_in(Inn,Iprofile),CT_in(Inn,Iprofile),p(Inn,Iprofile),Nsquared_lowerlimit_default,software_solver);
                        unstable = 1;
                    end
                    
                     
                    %--------------------------------------------------------------------------
                    % Final N2 test
                    %--------------------------------------------------------------------------
                    if length(Inn) > 1
                        [N2_tmp, N2_p_tmp, N2_specvol_tmp, N2_alpha_tmp, N2_beta_tmp, dSA_tmp, dCT_tmp, dp_tmp] = ...
                            gsw_Nsquared_min(SA_tmp,CT_tmp,p_tmp);
                    end
                    
                    [Iunstable] = find(N2_tmp - Nsquared_lowerlimit < 0);
                    if Number_of_iterations > 10 & ~isempty(Iunstable)  % Cannot correct when applying constraints, thus will return an unconstrained solution.
                        [Inn] = find(~isnan(SA_in(:,Iprofile) + CT_in(:,Iprofile) + p(:,Iprofile)));
                        [SA_tmp, CT_tmp] = gsw_stabilise_unconstrained_SA_CT(SA_in(Inn,Iprofile),CT_in(Inn,Iprofile),p(Inn,Iprofile),Nsquared_lowerlimit_default,software_solver);
                        unstable = 1;
                    end
                    
                    if isempty(Iunstable) 
                        unstable = 1;
                    end
                    
                end
                
                SA_out(Inn,Iprofile) = SA_tmp;
                CT_out(Inn,Iprofile) = CT_tmp;
                
            end
            
        else
            
            SA_out(Inn,Iprofile) = SA_in(Inn,Iprofile);
            CT_out(Inn,Iprofile) = CT_in(Inn,Iprofile);
            
        end
    end
end

if transposed
    SA_out = SA_out.';
    CT_out = CT_out.';
end

end

%##########################################################################

function [SA_unconstrained, CT_unconstrained] = gsw_stabilise_unconstrained_SA_CT(SA,CT,p,Nsquared_lowerlimit,software_solver)

% gsw_stabilise_unconstrained_SA_CT         minimally adjusts both Absolute
%                             Salinity and Conservative Temperature without
%           constraints to produce a stable water column (75-term equation)
%==========================================================================
%
% USAGE:
%  [SA_unconstrained, CT_unconstrained] = ...
%    gsw_stabilise_unconstrained_SA_CT(SA,CT,p,Nsquared_lowerlimit,software_solver)
%
% DESCRIPTION:
%  This function stabilises a water column, this is achieved by minimally
%  adjusting both the Absolute Salinity SA and Conservative Temperature CT
%  values such that the minimum stability is adjusted to be atleast
%  1 x 10^-9 s^-2, which is about 1/5th of the square of earth's rotation
%  rate.
%
%  This programme requires either the Optimization toolbox or Tomlab CPLEX.
%  if there are a up to several hundred data points in the cast then
%  Matlab's Optimization toolbox produces reasonable results, but if there
%  are thousands of bottles in the cast or the best possible output is
%  wanted then the CPLEX solver is required. This programme will determine
%  if Tomlab or the Optimization toolbox is available to the user, if both
%  are available it will use Tomlab.
%
%  Note that this 75-term equation has been fitted in a restricted range of
%  parameter space, and is most accurate inside the "oceanographic funnel"
%  described in McDougall et al. (2003).  The GSW library function
%  "gsw_infunnel(SA,CT,p)" is avaialble to be used if one wants to test if
%  some of one's data lies outside this "funnel".
%
% INPUT:
%  SA_tmp =  uncorrected Absolute Salinity                         [ g/kg ]
%  CT_tmp =  Conservative Temperature (ITS-90)                    [ deg C ]
%  p_tmp  =  sea pressure                                          [ dbar ]
%         ( i.e. absolute pressure - 10.1325 dbar )
%
%  Nsquared_lowerlimit = Nsquared lower limit                     [ 1/s^2 ]
%  software_solver = flag for which solver is called
%            1 is CPLEX from Tomlab and 
%            2 is the Optimization Toolbox from Matlab
%
%  SA_tmp, CT_tmp & p_tmp need to have the same dimensions.
%  Nsquared_lowerlimit must have dimensions (M-1)x1 where SA_tmp is Mx1.
%  software_solver must be a scalar and have dimensions 1x1.
%
% OUTPUT:
%  SA_unconstrained  =  corrected stablised Absolute Salinity      [ g/kg ]
%  CT_unconstrained  =  corrected stablised Conservative Temperature  
%                                                                 [ deg C ]
%
% AUTHOR:
%  Paul Barker and Trevor McDougall                    [ help@teos-10.org ]
%
% VERSION NUMBER: 3.05.5 (16th June, 2016)
%
% REFERENCES:
%  Barker, P.M., and T.J. McDougall, 2016: Stabilisation of hydrographic 
%    profiles.  J. Atmosph. Ocean. Tech., submitted.
%
%  IOC, SCOR and IAPSO, 2010: The international thermodynamic equation of
%   seawater - 2010: Calculation and use of thermodynamic properties.
%   Intergovernmental Oceanographic Commission, Manuals and Guides No. 56,
%   UNESCO (English), 196 pp.  Available from http://www.TEOS-10.org
%
%  McDougall, T.J., D.R. Jackett, D.G. Wright and R. Feistel, 2003:
%   Accurate and computationally efficient algorithms for potential
%   temperature and density of seawater.  J. Atmosph. Ocean. Tech., 20,
%   pp. 730-741.
%
%  Roquet, F., G. Madec, T.J. McDougall, P.M. Barker, 2015: Accurate
%   polynomial expressions for the density and specifc volume of seawater
%   using the TEOS-10 standard. Ocean Modelling, 90, pp. 29-43.
%
%  The software is available from http://www.TEOS-10.org
%
%  The Tomlab software is available from http://www.tomopt.com
%
%==========================================================================

%--------------------------------------------------------------------------
% Start of the calculation
%--------------------------------------------------------------------------

%  db2Pa = 1e4;
%  grav = 9.7963;% (Griffies, 2004)
c = 1.250423402612047e2; % c = 1.2*db2Pa./(grav.^2);

% Calculate Nsquared of the cast
[N2,dummy,specvol,alpha,beta,dSA,dCT,dp] = gsw_Nsquared_min(SA,CT,p);

% Determine if any of the bottle pairs have stabilities less than
% the Nsquared lower limit
if any(N2 - Nsquared_lowerlimit < 0)
    
    Name = 'stabilise the water column, adjusting SA and CT without constraints';
    Number_of_iterations = 0;
    unstable = 0;
    set_bounds = 1;
    
    while unstable < 1
        
        Number_of_iterations = Number_of_iterations + 1;
        
        alpha_beta = alpha./beta;
                
        b_U = beta.*dSA - alpha.*dCT - c*(Nsquared_lowerlimit.*dp).*specvol;
        % Note that c = 1.2*db2Pa./(grav.^2);
       
        %--------------------------------------------------------------------------
        % The solver
        %--------------------------------------------------------------------------
        switch software_solver
        %--------------------------------------------------------------------------
            
            case 1 % Tomlab CPLEX solver
                
                if set_bounds == 1
                    pl = length(p);
                    pl_pair = pl-1;
                    two_pl = 2*pl;
                    f = zeros(two_pl,1);
                    b_L = -inf*ones(pl_pair,1);
                    x_L = -inf*ones(two_pl,1);
                    x_U = inf*ones(two_pl,1);
                    x_0 = zeros(two_pl,1);
                    H_dummy = ones(two_pl,1);
                    A_s = pl_pair;
                    A_i = 2*A_s + 1;
                    A_e = A_i*(pl_pair-1);
                    A = zeros(pl_pair,two_pl);
                    set_bounds = 0;
                end
                
                H_dummy(2:2:(two_pl-2)) = alpha_beta.*alpha_beta;
                H = sparse(1:two_pl,1:two_pl, H_dummy);
                
                A([1:A_i:(A_e+1)]) = beta;
                A([A_s+1:A_i:(A_e+A_s+1)]) = -alpha;
                A([2*A_s+1:A_i:(A_e+2*A_s+1)]) = -beta;
                A([3*A_s+1:A_i:(A_e+3*A_s+1)]) = alpha;
                
                x_L(1:2:two_pl-1) = -SA;
                
                Prob = qpAssign(H, f, A, b_L, b_U, x_L, x_U, x_0, Name,[], [], [], [], []);
                Result = tomRun('cplex', Prob, 0);
                
                SA = SA + Result.x_k(1:2:two_pl-1);
                CT = CT + Result.x_k(2:2:two_pl);
                
        %--------------------------------------------------------------------------
                
            case 2 % Matlab solver
                
                if set_bounds == 1
                    pl = length(p);
                    pl_pair = pl-1;
                    two_pl = 2*pl;
                    f = zeros(two_pl,1);
                    x_L = -inf*ones(two_pl,1);
                    x_U = inf*ones(two_pl,1);
                    x_0 = zeros(two_pl,1);
                    H = eye(two_pl);
                    A_s = pl_pair;
                    A_i = 2*A_s + 1;
                    A_e = A_i*(pl_pair-1);
                    A = zeros(pl_pair,two_pl);
                    set_bounds = 0;
                end
                
                H([(two_pl+2):2*(two_pl+1):(4*pl*(pl-1)-2)]) = alpha_beta.*alpha_beta;
                
                A([1:A_i:(A_e+1)]) = beta;
                A([A_s+1:A_i:(A_e+A_s+1)]) = -alpha;
                A([2*A_s+1:A_i:(A_e+2*A_s+1)]) = -beta;
                A([3*A_s+1:A_i:(A_e+3*A_s+1)]) = alpha;
                
                x_L(1:2:two_pl-1) = -SA;
                
                if Number_of_iterations == 1
                    opts = optimset('Algorithm','active-set','Display','off');
                end
                
                x = quadprog(H, f, A, b_U, [], [], x_L, x_U, x_0, opts);
                
                SA = SA + x(1:2:two_pl-1);
                CT = CT + x(2:2:two_pl);
                
        %--------------------------------------------------------------------------
        end
        %--------------------------------------------------------------------------
        
        %--------------------------------------------------------------------------
        % Set limits and interpolate variables of any bottles
        % ouside of the limits
        %--------------------------------------------------------------------------
        CT(p < 100 & (CT > 80 | CT < -12)) = NaN;
        CT(p >= 100 & (CT > 40 | CT < -12)) = NaN;
        CT(SA > 120 | p > 12000) = NaN;
       
        if any(isnan(CT))
            [Inan] = find(isnan(SA + CT));
            [Inn2] = find(~isnan(SA + CT));
            if ~isempty(Inn2)
                [SA(Inan),CT(Inan)] = gsw_rr68_interp_SA_CT(SA(Inn2),CT(Inn2),p(Inn2),p(Inan));
                if any(isnan(SA + CT))
                    [Inan] = find(isnan(SA + CT));
                    [Inn2] = find(~isnan(SA + CT ));
                    if length(Inn2) > 1
                        [SA(Inan),CT(Inan)] = gsw_linear_interp_SA_CT(SA(Inn2),CT(Inn2),p(Inn2),p(Inan));
                    else
                        SA(Inn2) = NaN;
                        CT(Inn2) = NaN;
                        unstable = 1;
                        continue
                    end
                end
                set_bounds = 1;
            else
                continue
            end
        end
        %--------------------------------------------------------------------------
        
        [N2,dummy,specvol,alpha,beta,dSA,dCT,dp] = gsw_Nsquared_min(SA,CT,p);
        
        % N2 test
        [Iunstable] = find(N2 - Nsquared_lowerlimit < 0);
        if isempty(Iunstable) | Number_of_iterations > 10
            unstable = 1;
        end
        
    end
    SA_unconstrained = SA;
    CT_unconstrained = CT;
else
    SA_unconstrained = SA;
    CT_unconstrained = CT;
end

end

%##########################################################################

function [dSA_bottle, dCT_bottle] = gsw_stabilsation_constraints(SA_neutral,CT_neutral,p,Nsquared_lowlimit,pl,Imlp,N,software_solver)

% gsw_stabilsation_constraints           Absolute Salinity and Conservative 
%                                Temperature constraints (75-term equation)
%==========================================================================
%
% USAGE:
%  [dSA_bottle, dCT_bottle] = ...
%     gsw_stabilsation_constraints(SA_neutral,CT_neutral,p, ...
%                              Nsquared_lowlimit,pl,Imlp,N,software_solver)
%
% DESCRIPTION:
%  This function calculates the constraints dSA_bottle and dSA_bottle in a 
%  profile.  These constraints are based on a smoothed course resolution 
%  profile that has has SA and CT adjusted such that they are neutrally 
%  stabile.  We assume that a cast is neutrally stable then the minimum is 
%  greater of equal to 1 x 10^-9 s^-2, 1/5th of the square of earth's 
%  rotation rate.
%
%  Note that this 75-term equation has been fitted in a restricted range of
%  parameter space, and is most accurate inside the "oceanographic funnel"
%  described in McDougall et al. (2003).  The GSW library function
%  "gsw_infunnel(SA,CT,p)" is avaialble to be used if one wants to test if
%  some of one's data lies outside this "funnel".
%
% INPUT:
%  SA_neutral  =  neutrally stabilised Absolute Salinity           [ g/kg ]
%  CT_neutral  =  neutrally stabilised Conservative Temperature (ITS-90) 
%                                                                 [ deg C ]
%  p           =  sea pressure                                     [ dbar ]
%         ( i.e. absolute pressure - 10.1325 dbar )
%  Nsquared_lowlimit = minimum buoyancy (Brunt-Vaisala) frequency [ 1/s^2 ]
%                      squared (N^2)
%  pl          =  profile length
%  Imlp        =  index of where the pressure corresponds to the mixed 
%                 layer pressure
%  N           =  number of bottles used in the coarse resolution cast
%  software_solver   
%
%  SA_neutral, CT_neutral and p need to have the same dimensions.
%  Nsquared_lowlimit must have dimensions (M-1)x1 were SA_neutral, 
%  CT_neutral and p have dimensions Mx1.
%  pl, Imlp and N must be scalars and have dimensions 1x1.
%
% OUTPUT:
%  dSA_bottle  =  delta_SA, Absolute Salinity constraints        [ g/kg ]
%  dCT_bottle  =  delta_CT, Conservative Temperature constraints
%                                                                 [ deg C ]
%
% AUTHOR:
%  Paul Barker and Trevor McDougall                    [ help@teos-10.org ]
%
% VERSION NUMBER: 3.05.5 (16th June, 2016)
%
% REFERENCES:
%  Barker, P.M., and T.J. McDougall, 2016: Stabilisation of hydrographic 
%    profiles.  J. Atmosph. Ocean. Tech., submitted.
%
%  IOC, SCOR and IAPSO, 2010: The international thermodynamic equation of
%   seawater - 2010: Calculation and use of thermodynamic properties.
%   Intergovernmental Oceanographic Commission, Manuals and Guides No. 56,
%   UNESCO (English), 196 pp.  Available from http://www.TEOS-10.org
%
%  McDougall, T.J., D.R. Jackett, D.G. Wright and R. Feistel, 2003:
%   Accurate and computationally efficient algorithms for potential
%   temperature and density of seawater.  J. Atmosph. Ocean. Tech., 20,
%   pp. 730-741.
%
%  Roquet, F., G. Madec, T.J. McDougall, P.M. Barker, 2015: Accurate
%   polynomial expressions for the density and specifc volume of seawater
%   using the TEOS-10 standard. Ocean Modelling, 90, pp. 29-43.
%
%  The software is available from http://www.TEOS-10.org
%
%==========================================================================

if pl > N
    % There are lots of bottles, reduce them down to N bottles, this is 
    % used to determine a smooth profile.
    rf = (pl-Imlp)/N;
    
    p_smooth = nan(N,1);
    SA_smooth = p_smooth;
    CT_smooth = p_smooth;
    Nsquared_lowlimit_smooth = nan(N-1,1);
    
    I = 1;
    Iupper = Imlp;
    Ilower = Imlp + ceil(2*rf);
    Ilower(Ilower > pl) = pl;
    Iupper(Iupper >= Ilower) = Imlp - 1;
    
    SA_fit = polyfit(p(Iupper:Ilower),SA_neutral(Iupper:Ilower),1);
    CT_fit = polyfit(p(Iupper:Ilower),CT_neutral(Iupper:Ilower),1);
    SA_smooth(I) = polyval(SA_fit,p(Iupper));
    CT_smooth(I) = polyval(CT_fit,p(Iupper));
    p_smooth(I) = p(Iupper);
    for I = 2:N-1
        Iupper = Imlp + floor(rf*((I-1) - 0.5)) ;
        Iupper(Iupper < Imlp) = Imlp;
        Ilower = Imlp + ceil(rf*(I + 0.5)) ;
        Ilower(Ilower > pl) = pl;
        
        SA_smooth(I) = mean(SA_neutral(Iupper:Ilower));
        CT_smooth(I) = mean(CT_neutral(Iupper:Ilower));
        p_smooth(I) = mean(p(Iupper:Ilower));
        Nsquared_lowlimit_smooth(I-1) = max(Nsquared_lowlimit(Iupper:Ilower-1));
    end
    I = N;
    Iupper = pl - floor(2*rf);
    Iupper(Iupper == pl) = pl - 1;
    Ilower = pl;
    
    SA_fit = polyfit(p(Iupper:Ilower),SA_neutral(Iupper:Ilower),1);
    CT_fit = polyfit(p(Iupper:Ilower),CT_neutral(Iupper:Ilower),1);
    SA_smooth(I) = polyval(SA_fit,p(Ilower));
    CT_smooth(I) = polyval(CT_fit,p(Ilower));
    p_smooth(I) = p(Ilower);
    Nsquared_lowlimit_smooth(I-1) = max(Nsquared_lowlimit(Iupper:Ilower-1));
        
    % Make sure the background cast is stable. If any
    % bottles are not stable adjust SA and CT to force them to be.
    [N2_smooth, dummy,dummy,dummy,dummy,dummy,dummy,dummy] = gsw_Nsquared_min(SA_smooth,CT_smooth,p_smooth);
    if any((N2_smooth - Nsquared_lowlimit_smooth) < 0)
        [SA_smooth,CT_smooth] = gsw_stabilise_unconstrained_SA_CT(SA_smooth,CT_smooth,p_smooth,Nsquared_lowlimit_smooth,software_solver);
        [Inan_smooth] = find(isnan(SA_smooth + CT_smooth));
        if ~isempty(Inan_smooth)
            [Inn_smooth] = find(~isnan(SA_smooth + CT_smooth));
            [SA_smooth, CT_smooth] = gsw_linear_interp_SA_CT(SA_smooth(Inn_smooth), CT_smooth(Inn_smooth),p_smooth(Inn_smooth),p_smooth);
            SA_smooth = SA_smooth(:);
            CT_smooth = CT_smooth(:);
        end
        
    end
    
    % Stable cast relative to the bottle values.
    % Note. For the bottles in the mlp we will apply the direction that
    % occurs just below the mlp.
    
    rho_neutral = gsw_rho(SA_neutral,CT_neutral,p);
    rho_smooth = gsw_rho(SA_smooth,CT_smooth,p_smooth);
    
    dSA_smooth_bottle = nan(N,1);
    dCT_smooth_bottle = dSA_smooth_bottle;
    dSA_smooth_bottle(1) = SA_smooth(2) - SA_smooth(1);
    dCT_smooth_bottle(1) = CT_smooth(2) - CT_smooth(1);
    for I = 2:N-1
        dSA_smooth_bottle(I) = 0.5*(SA_smooth(I+1) - SA_smooth(I-1));
        dCT_smooth_bottle(I) = 0.5*(CT_smooth(I+1) - CT_smooth(I-1));
    end
    dSA_smooth_bottle(N) = SA_smooth(N) - SA_smooth(N-1);
    dCT_smooth_bottle(N) = CT_smooth(N) - CT_smooth(N-1);
    
    % Calculate r (distance from stable smoothed background bottle to cast
    % bottles). Based on pressure.
    r = nan(pl,1);
    dSA_bottle = r;
    dCT_bottle = r;
    
    % Data in the mlp based on the uppper most stable layer (I = 1).
    I = 1;
    [Idata] = find(p < p_smooth(I));
    r(Idata) = (rho_smooth(I) - rho_neutral(Idata))./(rho_smooth(I+1) - rho_smooth(I));
    dSA_bottle(Idata) = dSA_smooth_bottle(I) + r(Idata)*(dSA_smooth_bottle(I+1) - dSA_smooth_bottle(I));
    dCT_bottle(Idata) = dCT_smooth_bottle(I) + r(Idata)*(dCT_smooth_bottle(I+1) - dCT_smooth_bottle(I));
    for I = 1:N-2
        [Idata] = find(p >= p_smooth(I) & p < p_smooth(I+1));
        r(Idata) = (rho_neutral(Idata) - rho_smooth(I))./(rho_smooth(I+1) - rho_smooth(I));
        dSA_bottle(Idata) =  dSA_smooth_bottle(I) + r(Idata)*(dSA_smooth_bottle(I+1) - dSA_smooth_bottle(I));
        dCT_bottle(Idata) =  dCT_smooth_bottle(I) + r(Idata)*(dCT_smooth_bottle(I+1) - dCT_smooth_bottle(I));
    end
    I = N-1;
    [Idata] = find(p >= p_smooth(I) & p <= p_smooth(I+1));
    r(Idata) = (rho_neutral(Idata) - rho_smooth(I))./(rho_smooth(I+1) - rho_smooth(I));
    dSA_bottle(Idata) =  dSA_smooth_bottle(I) + r(Idata)*(dSA_smooth_bottle(I+1) - dSA_smooth_bottle(I));
    dCT_bottle(Idata) =  dCT_smooth_bottle(I) + r(Idata)*(dCT_smooth_bottle(I+1) - dCT_smooth_bottle(I));
    
else % not so many bottles
    
    % Make sure the background cast is stable. If any
    % bottles are not stable adjust SA to force them to be.
    [N2_neutral,p_mid_neutral,dummy,dummy,dummy,dummy,dummy,dummy] = gsw_Nsquared_min(SA_neutral(Imlp:pl),CT_neutral(Imlp:pl),p(Imlp:pl));
    if any((N2_neutral - Nsquared_lowlimit(Imlp:pl-1)) < 0)
        SA_stable(1:Imlp-1) = SA_neutral(1:Imlp-1); % these bottles are never used.
        CT_stable(1:Imlp-1) = CT_neutral(1:Imlp-1);
        [SA_stable(Imlp:pl),CT_stable(Imlp:pl)] = gsw_stabilise_unconstrained_SA_CT(SA_neutral(Imlp:pl),CT_neutral(Imlp:pl),p(Imlp:pl),Nsquared_lowlimit(Imlp:pl-1),software_solver);
        [Inan_stable] = find(isnan(SA_stable + CT_stable));
        if ~isempty(Inan_stable)
            [Inn_stable] = find(~isnan(SA_stable + CT_stable));
            [SA_stable, CT_stable] = gsw_linear_interp_SA_CT(SA_stable(Inn_stable), CT_stable(Inn_stable),p(Inn_stable),p);
            SA_stable = SA_stable(:);
            CT_stable = CT_stable(:);
        end
        
    else
        SA_stable = SA_neutral;
        CT_stable = CT_neutral;
    end
    
    % calculate dSA and dCT
    dSA_bottle = NaN(pl,1);
    dCT_bottle = dSA_bottle;
    
    % For bottles in the mlp use the first bottle pair
    % below the mlp
    I = 1;
    dSA_bottle(I:Imlp) = (SA_stable(Imlp+1) - SA_stable(Imlp));
    dCT_bottle(I:Imlp) = (CT_stable(Imlp+1) - CT_stable(Imlp));
    
    for I = Imlp+1:pl-1;
        dSA_bottle(I) = (SA_stable(I+1) - SA_stable(I-1));
        dCT_bottle(I) = (CT_stable(I+1) - CT_stable(I-1));
    end
    I = pl;
    dSA_bottle(I) = (SA_stable(I) - SA_stable(I-1));
    dCT_bottle(I) = (CT_stable(I) - CT_stable(I-1));
    
end

end