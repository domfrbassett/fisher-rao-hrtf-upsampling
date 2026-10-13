function recon = unavailable_reconstruction(sparseField, targetR, methodName, message)

    recon = sparseField;
    recon.r = targetR;
    recon.azElDeg = cartesian_to_az_el(targetR);
    recon.methodName = methodName;
    recon.isAvailable = false;
    recon.message = message;

end
