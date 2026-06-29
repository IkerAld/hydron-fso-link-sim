% startup.m
% Adds selected project sub-directories to the MATLAB path

clc;
disp('Initializing HydRON Simulation Environment...');

project_root = fileparts(mfilename('fullpath'));

% Folders to add (use genpath for folders that should include subfolders)
folders = { 'link_budget', 'simulation' };
use_genpath = [ true, true, true, true ]; % set true to include subfolders, false for top-level only

for k = 1:numel(folders)
    p = fullfile(project_root, folders{k});
    if use_genpath(k)
        addpath(genpath(p));
    else
        addpath(p);
    end
end

disp('Paths added successfully. Ready to run simulations.');