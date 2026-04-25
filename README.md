# Fiji_SG_Analysis_Macro
A custom ImageJ macro that uses StarDist and Cellpose to identify and segment nuclei, cells, and stress granules in fluorescence microscopy images.

See this video for installation: https://youtu.be/X9nwBuUy6Mk
See this video for tutorial and analysis steps: https://youtu.be/dzxV055w9J0

INSTALLATION INSTRUCTIONS:

1. Extract this zip file into your Fiji plugins folder.
Typically, Fiji is saved to the User directory. On Windows the file path looks like: 

C:\Users\(Your Username)\Fiji.app\plugins

Or, if Fiji.app is elsewhere, extract the folder to that location.
 
2. Restart Fiji, and the macros will show up in plugins menu in Fiji.


DEPENDENCIES:

Cellpose is required for the full macro. 
	You must install Cellpose separately of Fiji and create additional .bat files for proper function.
	To install Cellpose for this macro, see the YouTube video within the macro GUI when it runs.

StarDist and LabKit (and their dependencies) are required Fiji plugins. The macro will warn if you are missing any.

The Cellpose SAM model and LabKit classifiers are also required, but are included in the macro folder. Do not delete them.

TROUBLESHOOTING KNOWN ISSUES:

If the SG % calculation does not work for you, or reports 100% SG positive for all images, do the following:
    1. Open ImageJ/Fiji
    2. Go to Process > Binary > Options...
    3. Check the checkbox that says "Black Background"
    4. Click "OK"
    The % calculation should work now.
