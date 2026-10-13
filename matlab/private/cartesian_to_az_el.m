function azElDeg = cartesian_to_az_el(r)

    r = r ./ vecnorm(r, 2, 2);
    [azimuth, elevation, ~] = cart2sph(r(:, 1), r(:, 2), r(:, 3));
    azElDeg = rad2deg([azimuth, elevation]);

end
