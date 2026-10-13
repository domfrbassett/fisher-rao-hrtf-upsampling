function sparseField = subset_spatial_field(field, retainedIndices)

    sparseField = field;
    sparseField.r = field.r(retainedIndices, :);
    sparseField.azElDeg = field.azElDeg(retainedIndices, :);
    sparseField.hrir = field.hrir(retainedIndices, :, :);
    sparseField.complexHrtf = field.complexHrtf(retainedIndices, :, :);
    sparseField.hrtfMag = field.hrtfMag(retainedIndices, :, :);
    sparseField.retainedIndices = retainedIndices;

end
