%% Clear
clear, clc;

%% Set images
cb_img_paths = {'test/test_images/left01.jpg'};
                     
% Validate all calibration board images
cb_imgs = class.img.validate_similar_imgs(cb_img_paths);
                     
%% Load calibration config file
cal_config = util.load_cal_config('test/stereo.conf');

%% Get four points in pixel coordinates per calibration board image
four_points_ps = {};
switch cal_config.calibration
    case 'four_point_auto'
        error('Automatic four point detection has not been implemented yet');
    case 'four_point_manual'
        % Four points are selected manually
        [~, four_points_w] = alg.cb_points(cal_config);

        four_points_ps{1} = [244 94;
                             249 254;
                             479 86;
                             476 264];
                         
        % Refine
        for i = 1:length(four_points_ps)
            four_points_ps{i} = alg.refine_points(four_points_ps{i}, ...
                                                  cb_imgs(i), ...
                                                  alg.homography(four_points_w,four_points_ps{i},cal_config), ...
                                                  cal_config);  %#ok<SAGROW>
        end   
end

%% Perform single calibration
[A,distortion,rotations,translations,board_points_ps,homographies_refine] = alg.single_calibrate(cb_imgs, ...
                                                                                                 four_points_ps, ...
                                                                                                 cal_config);

%% Debug with gui
f = figure(2);
debug.gui_single(cb_imgs, ...
                 board_points_ps, ...
                 four_points_ps, ...
                 A, ...
                 distortion, ...
                 rotations, ...
                 translations, ...
                 homographies_refine, ...
                 cal_config, ...
                 f);