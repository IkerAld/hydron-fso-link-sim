% startup.m
% Adds all project subdirectories to the MATLAB path

clc;
disp('Initializing HydRON Simulation Environment...');

% Get the absolute path of the root directory
project_root = fileparts(mfilename('fullpath'));

% Add the src directory and all its subdirectories to the path
addpath(genpath(fullfile(project_root, 'src')));

% Add the main_scripts directory
addpath(fullfile(project_root, 'data'));

% Add the src directory and all its subdirectories to the path
addpath(genpath(fullfile(project_root, 'data')));

disp('Paths added successfully. Ready to run simulations.');