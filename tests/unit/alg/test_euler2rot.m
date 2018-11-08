function test_euler2rot
    euler = [0.1; 0.2; 0.3];
    R = alg.euler2rot(euler);

    % Assert
    assert(all(all(abs(R - [0.936293363584199  -0.275095847318244   0.218350663146334; ...
                            0.289629477625516   0.956425085849232  -0.036957013524625; ...
                           -0.198669330795061   0.097843395007256   0.975170327201816]) < eps('single'))));
    assert(all(abs(alg.rot2euler(R)-euler) < eps('single')));
end
