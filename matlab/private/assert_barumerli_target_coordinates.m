function assert_barumerli_target_coordinates(features, expectedR, tolerance)
% Fail if AMT target features no longer preserve the physical grid ordering.

    assert(isfield(features, "coords") && ~isempty(features.coords), ...
        "Barumerli target features do not contain source coordinates.");
    featureR = double(features.coords.return_positions('cartesian'));
    featureR = featureR ./ vecnorm(featureR, 2, 2);
    expectedR = expectedR ./ vecnorm(expectedR, 2, 2);
    assert(isequal(size(featureR), size(expectedR)), ...
        "Barumerli target feature coordinates do not match the reference grid.");
    maximumDifference = max(abs(featureR - expectedR), [], "all");
    assert(maximumDifference <= max(10 * tolerance, 1e-9), ...
        "Barumerli target feature coordinates do not match the reference grid.");

end
