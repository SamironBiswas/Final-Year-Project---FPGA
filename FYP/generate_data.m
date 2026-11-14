% Target quotas based on the paper's 1:4 ratio (30,000 total)
target_arc = 6000;
target_normal = 24000;

X_arc = []; Y_arc = [];
X_normal = []; Y_normal = [];

disp('Starting dataset generation. This may take several minutes...');

while (size(X_arc, 1) < target_arc) || (size(X_normal, 1) < target_normal)

    % Force an arc if we still need arc frames; otherwise, force normal
    if size(X_arc, 1) < target_arc
        t_fault = 0.2 + 0.5 * rand(); % Arc ignites between 0.2s and 0.7s
    else
        t_fault = 10.0; % Push fault outside simulation time (Normal mode)
    end

    % 50V DC source as per the experimental setup
    assignin('base', 'sim_Vdc', 50); 
    assignin('base', 'sim_Iload', 3 + 4 * rand()); 
    assignin('base', 'sim_t_fault', t_fault);

    % Randomize the switching period for the parallel load (transient simulation)
    assignin('base', 'sim_pulse_period', 0.02 + 0.1 * rand()); 

    % Run simulation
    simOut = sim('cktfyp', 'StopTime', '1.0');

    current = simOut.sim_data(:, 1);
    labels = simOut.sim_data(:, 2);

    total_frames = floor(length(current) / 160);

    % Extract non-overlapping 160-sample windows
    for f = 1:total_frames
        idx = (f-1)*160 + 1 : f*160;
        frame_label = labels(idx);

        % Save to Arc quota
        if all(frame_label == 1) && size(X_arc, 1) < target_arc
            X_arc = [X_arc; current(idx)'];
            Y_arc = [Y_arc; 1];

            % Save to Normal quota
        elseif all(frame_label == 0) && size(X_normal, 1) < target_normal
            X_normal = [X_normal; current(idx)'];
            Y_normal = [Y_normal; 0];
        end
    end

    % Print progress update
    fprintf('Progress: %d/%d Arc | %d/%d Normal\n', ...
        size(X_arc,1), target_arc, size(X_normal,1), target_normal);
end

% Combine the datasets
X_data = [X_normal; X_arc];
Y_data = [Y_normal; Y_arc];

% Shuffle the final dataset to prevent sequential bias during CNN training
fprintf('Shuffling dataset...\n');
shuffle_idx = randperm(size(X_data, 1));
X_data = X_data(shuffle_idx, :);
Y_data = Y_data(shuffle_idx, :);

% Save to file
save('arc_dataset_fpga.mat', 'X_data', 'Y_data');
disp('Exact 30,000-frame dataset with 1:4 ratio successfully generated!');