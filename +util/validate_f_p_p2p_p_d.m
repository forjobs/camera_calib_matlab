function validate_f_p_p2p_p_d(f_p_p2p_p_d)
    % Makes sure input function handle is a valid distortion function.
    %
    % Inputs:
    %   f_p_p2p_p_d - function handle; describes the mapping between 
    %       pixel coordinates and distorted pixel coordinates.
    %
    % Outputs:
    %   none
    
    if ~startsWith(func2str(f_p_p2p_p_d),'@(x_p,y_p,a,x_o,y_o')
        error('Invalid distortion function handle; must start with "x_p,y_p,a,x_o,y_o"');
    end
end