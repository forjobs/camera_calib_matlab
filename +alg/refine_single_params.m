function [params,cov_params] = refine_single_params(params,p_cb_p_dss,idx_valids,f_p_w2p_p,f_dp_p_dh,f_p_p2p_p_d,f_dp_p_d_dargs,optimization_type,opts,cov_cb_p_dss)
    % This will compute nonlinear refinement of intrinsic and extrinsic
    % camera parameters.
    %
    % Inputs:
    %   params - array; (3+M+6*N)x1 array, where M is the number of 
    %       distortion parameters and N is the number of calibration 
    %       boards. Contains: 
    %           [alpha; x_o; y_o; d_1; ... d_M; ...
    %            theta_x1; theta_y1; theta_z1; t_x1; t_y1; t_z1; ... 
    %            theta_xN; theta_yN; theta_zN; t_xN; t_yN; t_zN]
    %   p_cb_p_dss - cell; Nx1 cell array of calibration board points in
    %       distorted pixel coordinates
    %   idx_valids - cell; Nx1 cell array of "valid" calibration board
    %       points
    %   f_p_w2p_p - function handle; function which transforms world
    %   	coordinates to pixel coordinates
    %   f_dp_p_dh - function handle; derivative of p_w2p_p wrt homography
    %       parameters.
    %   f_p_p2p_p_d - function handle; describes the mapping between 
    %       pixel coordinates and distorted pixel coordinates.
    %   f_dp_p_d_dargs - function handle; derivative of p_p2p_p_d wrt its
    %       input arguments.
    %   optimization_type - string; describes type of optimization
    %   opts - struct; 
    %       .height_fp - scalar; height of the "four point" box
    %       .width_fp - scalar; width of the "four point" box
    %       .num_targets_height - int; number of targets in the "height"
    %           dimension
    %       .num_targets_width - int; number of targets in the "width"
    %           dimension
    %       .target_spacing - scalar; space between targets
    %       .refine_single_params_lambda_init - scalar; initial lambda for 
    %           Levenberg-Marquardt method
    %       .refine_single_params_lambda_factor - scalar; scaling factor 
    %           for lambda
    %       .refine_single_params_it_cutoff - int; max number of iterations
    %           performed for refinement of camera parameters
    %       .refine_single_params_norm_cutoff - scalar; cutoff for norm of
    %           difference of parameter vector for refinement of camera
    %           parameters.
    %       .verbose - int; level of verbosity
    %   cov_cb_p_dss - cell; optional Nx1 cell array of covariances of
    %       calibration board points in distorted pixel coordinates.
    %
    % Outputs:
    %   params - array; (3+M+6*N)x1 array, where M is the number of 
    %       distortion parameters and N is the number of calibration 
    %       boards. Contains: 
    %           [alpha; x_o; y_o; d_1; ... d_M; ...
    %            theta_x1; theta_y1; theta_z1; t_x1; t_y1; t_z1; ... 
    %            theta_xN; theta_yN; theta_zN; t_xN; t_yN; t_zN]
    %   cov_params - array; (3+M+6*N)x(3+M+6*N) array of covariances of
    %       intrinsic and extrinsic parameters
    
    % Get board points in world coordinates
    p_cb_ws = alg.p_cb_w(opts);
    
    % Get number of boards
    num_boards = numel(p_cb_p_dss);
    
    % Get number of distortion params
    num_params_d = alg.num_params_d(f_p_p2p_p_d);
    
    % Determine which parameters to update based on type
    idx_update = false(size(params));
    switch optimization_type
        case 'intrinsic'
            % Only update camera matrix and distortion params
            idx_update(1:3+num_params_d) = true;
        case 'extrinsic'
            % Only update rotations and translations
            idx_update(3+num_params_d+1:end) = true;
        case 'full'
            % Update everything
            idx_update(1:end) = true;
        otherwise
            error(['Input type of: "' optimization_type '" was not recognized']);
    end
    
    % For single images, remove principle point from optimization
    if num_boards == 1
        idx_update(2:3) = false;
    end  
    
    % Get "weight matrix"
    if exist('cov_cb_p_dss','var')
        % Do generalized least squares
        % Get "weight" matrix (inverse of covariance)
        cov = vertcat(cov_cb_p_dss{:}); % Concat
        cov = cov(vertcat(idx_valids{:})); % Apply valid indices
        cov = cellfun(@sparse,cov,'UniformOutput',false); % Make sparse
        cov = blkdiag(cov{:}); % Create full covariance matrix
        W = inv(cov); % This might be slow...
    else
        % Identity weight matrix is just simple least squares
        W = speye(2*sum(vertcat(idx_valids{:})));
    end
    
    % Perform Levenberg–Marquardt iteration(s)
    % Initialize lambda
    lambda = opts.refine_single_params_lambda_init;
    % Get initial cost
    cost = calc_cost(params, ...
                     p_cb_ws, ...
                     p_cb_p_dss, ...
                     idx_valids, ...
                     f_p_w2p_p, ...
                     f_dp_p_dh, ...
                     f_p_p2p_p_d, ...
                     f_dp_p_d_dargs, ...
                     idx_update, ...
                     W);
    for it = 1:opts.refine_single_params_it_cutoff
        % Store previous params and cost
        params_prev = params;
        cost_prev = cost;
        
        % Compute delta_params
        delta_params = calc_delta_params(params_prev, ...
                                         p_cb_ws, ...
                                         p_cb_p_dss, ...
                                         idx_valids, ...
                                         f_p_w2p_p, ...
                                         f_dp_p_dh, ...
                                         f_p_p2p_p_d, ...
                                         f_dp_p_d_dargs, ...
                                         idx_update, ...
                                         lambda, ...
                                         W);
        
        % update params and cost
        params(idx_update) = params_prev(idx_update) + delta_params;        
        cost = calc_cost(params, ...
                         p_cb_ws, ...
                         p_cb_p_dss, ...
                         idx_valids, ...
                         f_p_w2p_p, ...
                         f_dp_p_dh, ...
                         f_p_p2p_p_d, ...
                         f_dp_p_d_dargs, ...
                         idx_update, ...
                         W);
        
        % If cost decreases, decrease lambda and store results; if cost
        % increases, then increase lambda until cost decreases
        if cost < cost_prev
            % Decrease lambda and continue to next iteration
            lambda = lambda/opts.refine_single_params_lambda_factor;
        else
            while cost >= cost_prev
                % Increase lambda and recompute params
                lambda = opts.refine_single_params_lambda_factor*lambda;      
                
                if lambda >= realmax('single')
                    % This will already be a very, very small step, so just
                    % exit
                    delta_params(:) = 0;
                    cost = cost_prev;
                    params = params_prev;
                    break
                end
                
                % Compute delta_params
                delta_params = calc_delta_params(params_prev, ...
                                                 p_cb_ws, ...
                                                 p_cb_p_dss, ...
                                                 idx_valids, ...
                                                 f_p_w2p_p, ...
                                                 f_dp_p_dh, ...
                                                 f_p_p2p_p_d, ...
                                                 f_dp_p_d_dargs, ...
                                                 idx_update, ...
                                                 lambda, ...
                                                 W);

                % update params and cost
                params(idx_update) = params_prev(idx_update) + delta_params;   
                cost = calc_cost(params, ...
                                 p_cb_ws, ...
                                 p_cb_p_dss, ...
                                 idx_valids, ...
                                 f_p_w2p_p, ...
                                 f_dp_p_dh, ...
                                 f_p_p2p_p_d, ...
                                 f_dp_p_d_dargs, ...
                                 idx_update, ...
                                 W);
            end            
        end
                       
        % Exit if change in distance is small
        diff_norm = norm(delta_params);
        
        % Print iteration stats
        [~, res] = calc_gauss_newton_params(params, ...
                                            p_cb_ws, ...
                                            p_cb_p_dss, ...
                                            idx_valids, ...
                                            f_p_w2p_p, ...
                                            f_dp_p_dh, ...
                                            f_p_p2p_p_d, ...
                                            f_dp_p_d_dargs, ...
                                            idx_update);
        res = reshape(res,2,[])'; % get in [x y] format
        d_res = sqrt(res(:,1).^2 + res(:,2).^2);
        util.verbose_disp(['It #: ' sprintf('% 3u',it) '; ' ...
                           'Median res dist: ' sprintf('% 12.8f',median(d_res)) '; ' ...
                           'MAD res dist: ' sprintf('% 12.8f',1.4826*median(abs(d_res - median(d_res)))) '; ' ...
                           'Norm of delta_p: ' sprintf('% 12.8f',diff_norm) '; ' ...
                           'Cost: ' sprintf('% 12.8f',cost) '; ' ...
                           'lambda: ' sprintf('% 12.8f',lambda)], ...
                           3, ...
                           opts);
        
        if diff_norm < opts.refine_single_params_norm_cutoff
            break
        end
    end    
    if it == opts.refine_single_params_it_cutoff
        warning('iterations hit cutoff before converging!!!');
    end
            
    % Get covariance of parameters
    [jacob, res] = calc_gauss_newton_params(params, ...
                                            p_cb_ws, ...
                                            p_cb_p_dss, ...
                                            idx_valids, ...
                                            f_p_w2p_p, ...
                                            f_dp_p_dh, ...
                                            f_p_p2p_p_d, ...
                                            f_dp_p_d_dargs, ...
                                            true(size(idx_update))); % Mark all as true for final covariance estimation
    [~,~,~,cov_params] = lscov(jacob,res,W);
end

function delta_params = calc_delta_params(params,p_ws,p_p_dss,idx_valids,f_p_w2p_p,f_dp_p_dh,f_p_p2p_p_d,f_dp_p_d_dargs,idx_update,lambda,W)
    % Get gauss newton params
    [jacob, res] = calc_gauss_newton_params(params, ...
                                            p_ws, ...
                                            p_p_dss, ...
                                            idx_valids, ...
                                            f_p_w2p_p, ...
                                            f_dp_p_dh, ...
                                            f_p_p2p_p_d, ...
                                            f_dp_p_d_dargs, ...
                                            idx_update);

    % Get gradient    
    grad = jacob'*W*res;
    
    % Get hessian
    hess = jacob'*W*jacob;
    
    % Add Levenberg–Marquardt damping
    hess = hess + lambda*eye(sum(idx_update));
          
    % Get change in params
    delta_params = -lscov(hess,grad);
end

function cost = calc_cost(params,p_ws,p_p_dss,idx_valids,f_p_w2p_p,f_dp_p_dh,f_p_p2p_p_d,f_dp_p_d_dargs,idx_update,W)               
    % Get residuals
    [~, res] = calc_gauss_newton_params(params, ...
                                        p_ws, ...
                                        p_p_dss, ...
                                        idx_valids, ...
                                        f_p_w2p_p, ...
                                        f_dp_p_dh, ...
                                        f_p_p2p_p_d, ...
                                        f_dp_p_d_dargs, ...
                                        idx_update);
    
    % Apply weights
    cost = res'*W*res;
end

function [jacob, res] = calc_gauss_newton_params(params,p_ws,p_p_dss,idx_valids,f_p_w2p_p,f_dp_p_dh,f_p_p2p_p_d,f_dp_p_d_dargs,idx_update)
    % Get number of boards
    num_boards = numel(p_p_dss);
    
    % Get number of distortion params    
    num_params_d = alg.num_params_d(f_p_p2p_p_d);
       
    % Get intrinsic parameters
    a = params(1:3);
    d = params(4:3+num_params_d);
    
    % Get residuals and jacobian
    res = zeros(2*sum(vertcat(idx_valids{:})),1);
    jacob = sparse(2*sum(vertcat(idx_valids{:})),numel(params));
    for i = 1:num_boards
        % Get rotation and translation for this board
        R = alg.euler2rot(params(3+num_params_d+6*(i-1)+1: ...
                                 3+num_params_d+6*(i-1)+3));
        t = params(3+num_params_d+6*(i-1)+4: ...
                   3+num_params_d+6*(i-1)+6);
        
        % Get homography
        H = alg.a2A(a)*[R(:,1) R(:,2) t];
        
        % Get pixel points
        p_ps = f_p_w2p_p(p_ws,H);
        
        % Get distorted pixel points
        p_p_d_ms = alg.p_p2p_p_d(p_ps,f_p_p2p_p_d,a,d);
            
        % Store residuals - take valid indices into account
        res(2*sum(vertcat(idx_valids{1:i-1}))+1:2*sum(vertcat(idx_valids{1:i}))) = ...
            reshape(vertcat((p_p_d_ms(idx_valids{i},1)-p_p_dss{i}(idx_valids{i},1))', ...
                            (p_p_d_ms(idx_valids{i},2)-p_p_dss{i}(idx_valids{i},2))'),[],1);
               
        % Intrinsics
        jacob(2*sum(vertcat(idx_valids{1:i-1}))+1:2*sum(vertcat(idx_valids{1:i})),1:3+num_params_d) = ...
            alg.dp_p_d_dintrinsic(p_ws(idx_valids{i},:),f_p_w2p_p,f_dp_p_dh,R,t,f_dp_p_d_dargs,a,d); %#ok<SPRIX>

        % Extrinsics
        dr_deuler = alg.dr_deuler(alg.rot2euler(R));
        drt_dm = blkdiag(dr_deuler,eye(3));
        jacob(2*sum(vertcat(idx_valids{1:i-1}))+1:2*sum(vertcat(idx_valids{1:i})),3+num_params_d+6*(i-1)+1:3+num_params_d+6*(i-1)+6) = ...
            alg.dp_p_d_dextrinsic(p_ws(idx_valids{i},:),f_p_w2p_p,f_dp_p_dh,R,t,f_dp_p_d_dargs,a,d,drt_dm); %#ok<SPRIX>
    end  
    
    % Only update specified parameters
    jacob = jacob(:,idx_update);    
end