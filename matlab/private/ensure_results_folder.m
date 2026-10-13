function ensure_results_folder(resultsRoot)

    if ~isfolder(resultsRoot)
        mkdir(resultsRoot);
    end

end
