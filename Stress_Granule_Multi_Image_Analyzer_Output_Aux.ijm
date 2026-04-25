// ImageJ Macro: Multi Image Stress Granule Analyzer
// Developed for the Smaldino Lab by Chance Creviston, written primarily by ChatGPT and Google Gemini
// Channel 1 must be DAPI (nuclei). SG channel is interchangable. Auxiliary channel can be selected to measure mean intensity within cell boundaries.

// -----------------------------------------------------------
// INITIALIZE (Close Open Images)
// -----------------------------------------------------------
#@ File (label = "Input Directory", style = "directory") inputDir
#@ String (visibility=MESSAGE, label=" ", value="<html><u>PIPELINE DESCRIPTIONS") msg1
#@ String (visibility=MESSAGE, label=" ", value="<html>TRI-NET (GPU): High-Accuracy. Powered by 3 machine learning models to segment and analyze cells. <br>StarDist: identify nuclei<br>Cellpose SAM: identify cytoplasm<br>LabKit: determine whether cells are SG+/-<br><b>Requires NVIDIA GPU, Cellpose, and Cellpose SAM (CPSAM) custom model.") msg2
#@ String (visibility=MESSAGE, label=" ", value="<html>DUAL-NET (CPU): Medium-Accuracy. Only uses 2 machine learning models as Cellpose cannot run on CPUs.<br>StarDist: identify nuclei<br>LabKit: identify cytoplasm<br>LabKit: determine whether cells are SG+/-<br>IF CYTO CLASSIFIER FILE IS NOT AVAILABLE: Uses circular masks surrounding nuclei to estimate cytoplasms.") msg3
#@ String (label = "Segmentation Mode", choices={"Tri-Net (Recommended, GPU Required)", "Dual-Net (CPU)"}, style="radioButtonHorizontal") run_mode
#@ String (label = "Batch Mode", choices={"Limit Window Pop-Ups (Faster)", "Show All Windows (Slower)"}, style="radioButtonHorizontal") batch_mode_global
#@ String (label = "Stress Granule Channel", choices={"Channel 2", "Channel 3", "Channel 4"}, style="radioButtonHorizontal") sg_channel_choose
#@ String (label = "Auxiliary Channel (e.g. Poly-GR)", choices={"None", "Channel 2", "Channel 3", "Channel 4"}, style="radioButtonHorizontal") aux_channel_choose
#@ String (label = "Name of Aux Protein (No Comma)", value="PolyGR") aux_protein_name
#@ String (visibility=MESSAGE, label=" ", value="<html>Tutorial and more information about the macro: <a href='https://youtu.be/dzxV055w9J0'>https://youtu.be/dzxV055w9J0</a></html>") msg4
#@ String (visibility=MESSAGE, label=" ", value="<html>How to install Cellpose for this macro: <a href='https://youtu.be/X9nwBuUy6Mk'>https://youtu.be/X9nwBuUy6Mk</a></html>") msg5
#@ String (visibility=MESSAGE, label=" ", value="<html>See these helpful Cellpose videos:<br>Cellpose 2.0 Tutorial: <a href='https://www.youtube.com/watch?v=5qANHWoubZU'>https://www.youtube.com/watch?v=5qANHWoubZU</a><br>Cellpose SAM Tutorial: <a href='https://www.youtube.com/watch?v=KIdYXgQemcI'>https://www.youtube.com/watch?v=KIdYXgQemcI</a></html>") msg6
#@ String (visibility=MESSAGE, label=" ", value="<html><i>*Note: this macro <u>must</u> partially run outside of batch mode for cytoplasmic segmentation to function properly.") msg7

// A. Force Output to be same as Input
outputDir = inputDir + File.separator;
pipeline = ""
if (startsWith(run_mode, "Tri-Net")) {
    pipeline = "Tri-Net (GPU)";
} else {
    pipeline = "Dual-Net (CPU)";
}

batch_logic = false; // Default to slow/visible
if (indexOf(batch_mode_global, "Limit") >= 0) {
    batch_logic = true;
}
setBatchMode(false);

n = nImages;
if (n > 0) {
        waitForUser("Warning","This macro will close all currently open images.\n \n" +
        "Click OK to continue.");
    }
    
// B. Print Dynamic Title based on User Selection
var macro_version = "";
if (startsWith(run_mode, "Tri-Net")) {
    macro_version = "v1.0 (Q11-Heavy)";
} else {
    macro_version = "v1.0 (Q10-Light)";
}
var macro_title = "";
if (startsWith(run_mode, "Tri-Net")) {
    macro_title = "SG Tri-Net Image Analysis (GPU)";
} else {
    macro_title = "SG Dual-Net Image Analysis (CPU)";
}

if (isOpen("Log")) {
    selectWindow("Log");
}
print("\nStarting " + macro_title + " - Version: " + macro_version);
print("Segmentation Mode: " + run_mode);

run("Close All");

// -----------------------------------------------------------
// 0. SYSTEM HEALTH CHECK (Dependencies)
// -----------------------------------------------------------
// A. Populate the internal list with every command currently installed
List.setCommands; 
all_commands = List.getList; // Grabs the full list as one giant string

// B. Define the exact command names we need
// Note: We use partial names (e.g. "StarDist 2D") to be safe against version changes
required_plugins = newArray(
    "StarDist 2D", 
    "Cellpose ...", 
    "Segment Image With Labkit"
);

// C. Define Central Path for Classifiers
// Tell the code what files you're looking for
classifier_name_SG_pct = "NPC LabKit Classifier 6.0 - High Detection.classifier";
classifier_name_cyto_area = "NPC LabKit Classifier 6.1 - High Detection.classifier";

// Search for SG % Classifier in plugins and macros
path_sg_preferred = getDirectory("imagej") + "plugins" + File.separator + "Stress_Granule_Analyzers" + File.separator + classifier_name_SG_pct;
path_sg_fallback  = getDirectory("imagej") + "macros" + File.separator + classifier_name_SG_pct;

if (File.exists(path_sg_preferred)) {
    classifier_path_SG_pct = path_sg_preferred;
} else {
    classifier_path_SG_pct = path_sg_fallback; // Use fallback even if it doesn't exist (we check later)
}

// Search for Cyto Area Classifier in plugins and macros
path_cyto_preferred = getDirectory("imagej") + "plugins" + File.separator + "Stress_Granule_Analyzers" + File.separator + classifier_name_cyto_area;
path_cyto_fallback  = getDirectory("imagej") + "macros" + File.separator + classifier_name_cyto_area;

if (File.exists(path_cyto_preferred)) {
    classifier_path_cyto_area = path_cyto_preferred;
} else {
    classifier_path_cyto_area = path_cyto_fallback;
}

// D. Check for the commands we will need
missing_log = "";
for (i = 0; i < required_plugins.length; i++) {
    req = required_plugins[i];
    // indexOf returns -1 if the string is NOT found
    if (indexOf(all_commands, req) == -1) {
        missing_log = missing_log + "- " + req + "\n";
    }
}
for (i = 0; i < required_plugins.length; i++) {
    req = required_plugins[i];
    // SKIP CHECK: If running CPU mode, ignore Cellpose missing
    if (startsWith(run_mode, "Dual-Net") && indexOf(req, "Cellpose") >= 0) {
        continue; 
    }
    if (indexOf(all_commands, req) == -1) {
        missing_log = missing_log + "- " + req + "\n";
    }
}

// E. Search for Cellpose and CPSAM Model
// 1. Get the current user's home folder automatically
user_home = getDirectory("home");

// 2. Build the rest of the path dynamically
cellpose_env_path = user_home + "miniforge3" + File.separator + "envs" + File.separator + "cellpose";

// 3. Print it to the Log just to check
print("Found User Cellpose Path: " + cellpose_env_path);

// 4. Define Model Name
CPSAM_model_name = "2025_12_13_CPSAM_Find_Cyto_w_G3BP1";

// 5. Define Paths
model_path_plugin = getDirectory("imagej") + "plugins" + File.separator + "Stress_Granule_Analyzers" + File.separator + CPSAM_model_name;
model_path_fallback = "[C:\\Users\\g\\Documents\\Smaldino Lab 12-1-25\\Immunofluorescence\\2025_11_17_NPC-C9-70_250uM_CONTAMINATED\\CPSAM Training Images\\models\\" + CPSAM_model_name + "]"; // Keep your local dev path as backup

// 6. Logic to select the right one
if (File.exists(model_path_plugin)) {
    CPSAM_model_path = model_path_plugin;
} else {
    CPSAM_model_path = model_path_fallback;
}

// F. Alert the user if anything is missing
if (lengthOf(missing_log) > 0) {
    waitForUser("Critical Dependencies Missing", 
        "This macro requires specific plugins that were not found:\n\n" + 
        missing_log + 
        "\nPlease install them via ImageJ > Help > Update... > Manage Update Sites:\n" +
        "1. StarDist\n    a. TensorFlow2.\n    b. CSBDeep\n" +
        "2. PTBIOP (for Cellpose)\n    a. IBMP-CNRS\n    b. ImageScience\n" +
        "3. LabKit\n \n" +
        "Each of these has additional dependencies.\n \n" +
        "The macro will likely crash if you continue.\n \n" +
        "WARNING: YOU MUST INSTALL CELLPOSE SEPARATELY OF IMAGEJ\n" +
        "YOU MUST HAVE THE CUSTOM CPSAM MODEL: 2025_12_13_CPSAM_Find_Cyto_w_G3BP1 (TRAINED BY CHANCE CREVISTON)\n\n" +
        "For installation instructions, see: https://github.com/MouseLand/cellpose?tab=readme-ov-file#readme\n" +
        "You must update the Cellpose application and model file paths in macro code.");
}
if (!File.exists(classifier_path_SG_pct)) {
    showMessage("SG Classifier Not Found", "Could not find the SG % classifier in the Fiji/macros folder.\nPlease download/move the 'NPC LabKit Classifier 6.0 - High Detection.classifier' File to the Fiji.app 'macros' folder or to Fiji.app/plugins/Stress_Granule_Analyzers.\nPercent SG positive calculation will not be available without this file.");
}
if (startsWith(run_mode, "Dual-Net")) {
if (!File.exists(classifier_path_cyto_area)) {
    showMessage("Cytoplasmic Classifier Not Found", "Could not find the cytoplasm classifier in the Fiji/macros folder.\nPlease download/move the 'NPC LabKit Classifier 6.1 - High Detection.classifier' File to the Fiji.app 'macros' folder or to Fiji.app/plugins/Stress_Granule_Analyzers.\nCell areas will be calculated via inaccurate maximum masking. Average cell area will not be available without this file.");
	}
}

// -----------------------------------------------------------
// 1. DEFINE CHANNELS AND SG SIZE VARIABLES
// -----------------------------------------------------------
// A. Define "Small" vs "Large" Stress Granules
split_point = 1.0; // SGs smaller than this are "Small", larger are "Large"

// B. Set channel indices (adjust if needed)
nuclei_channel = 1; // Always DAPI

// 1. Setup Stress Granule Channel
if (sg_channel_choose == "Channel 2") sg_channel = 2;
else if (sg_channel_choose == "Channel 3") sg_channel = 3;
else sg_channel = 4;

// 2. Setup Auxiliary Channel
analyze_aux = true; // Default to yes
aux_channel = 0;    // Default placeholder

if (aux_channel_choose == "None") {
    analyze_aux = false;
    print("Configuration: Auxiliary Channel SKIPPED.");
} else {
    if (aux_channel_choose == "Channel 2") aux_channel = 2;
    else if (aux_channel_choose == "Channel 3") aux_channel = 3;
    else aux_channel = 4;

    // Safety Check: Did user select the SAME channel for both?
    if (aux_channel == sg_channel) {
        waitForUser("WARNING: You selected Channel " + aux_channel + " for both SG and Auxiliary.");
    }
}

// C. Set minimum object sizes (in pixels)
min_nucleus_size = 30; //variable not used anymore after switch to StarDist nucleus counting
min_sg_size = 0.2;
max_sg_size = 10;

// -----------------------------------------------------------
// 2. SETUP OUTPUT FILES
// -----------------------------------------------------------
timestamp = getTime();
timestampStr = d2s(timestamp / 1000, 0);

// User defines input and output directories
//inputDir = getDirectory("Choose Input Folder");
list = getFileList(inputDir);

// Define Paths
summaryPath = outputDir + "Batch_Summary_" + timestampStr + ".csv";
SGdetailedPath = outputDir + "Batch_SG_Detailed_" + timestampStr + ".csv";
nucleiDetailedPath = outputDir + "Batch_Nuclei_Detailed_" + timestampStr + ".csv";
cellDetailedPath = outputDir + "Batch_Cell_Detailed_" + timestampStr + ".csv";
auxDetailedPath = outputDir + "Batch_" + aux_protein_name + "_Detailed_" + timestampStr + ".csv";

// Define Headers (Updated for Small vs Large sorting)
// Note: We leave \n here because this is the header row.
// [Update this line at the top]
summaryHeader = "Filename,Pipeline,Nuclei_Count,Avg_Nucleus_Area,Avg_Cytoplasm_Area,Avg_Nucleus_Diameter,n_SG_Positive_Cells,%_SG_Positive,Total_SG_Count,Small_SGs,Large_SGs,SGs_per_Cell,Small_per_Cell,Large_per_Cell,Total_SG_Area_um2,Avg_Global_Area,Avg_Small_Area,Avg_Large_Area,SD_Global_Area,SD_Small_Area,SD_Large_Area,Var_Global_Area,Var_Small_Area,Var_Large_Area,Avg_Global_Int,Avg_Small_Int,Avg_Large_Int,Avg_Global_Circ,Avg_Small_Circ,Avg_Large_Circ,Avg_Global_Solid,Avg_Small_Solid,Avg_Large_Solid,Avg_Global_Feret,Avg_Small_Feret,Avg_Large_Feret";
if (analyze_aux) {
    // We take the user's string (e.g., "TDP43") and build the column title
    summaryHeader = summaryHeader + ",Avg_" + aux_protein_name + "_Mean,Avg_" + aux_protein_name + "_IntDen";
}
summaryHeader = summaryHeader + "\n";
SGdetailedHeader = "Filename,SG_ID,Size_Class,Area,Mean,StdDev,Mode,Min,Max,X,Y,XM,YM,Perim.,BX,BY,Width,Height,Major,Minor,Angle,Circ.,Feret,IntDen,Median,Skew,Kurt,%Area,RawIntDen,Slice,FeretX,FeretY,FeretAngle,MinFeret,AR,Round,Solidity\n";
nucleiHeader = "Filename,Nucleus_ID,Area,Mean,StdDev,Mode,Min,Max,X,Y,XM,YM,Perim.,BX,BY,Width,Height,Major,Minor,Angle,Circ.,Feret,IntDen,Median,Skew,Kurt,%Area,RawIntDen,Slice,FeretX,FeretY,FeretAngle,MinFeret,AR,Round,Solidity\n";
cellHeader = "Filename,Cell_ID,Area,Mean,StdDev,Mode,Min,Max,X,Y,XM,YM,Perim.,BX,BY,Width,Height,Major,Minor,Angle,Circ.,Feret,IntDen,Median,Skew,Kurt,%Area,RawIntDen,Slice,FeretX,FeretY,FeretAngle,MinFeret,AR,Round,Solidity\n";
auxHeader = "Filename,Cell_ID,Area,Mean,StdDev,Mode,Min,Max,X,Y,XM,YM,Perim.,BX,BY,Width,Height,Major,Minor,Angle,Circ.,Feret,IntDen,Median,Skew,Kurt,%Area,RawIntDen,Slice,FeretX,FeretY,FeretAngle,MinFeret,AR,Round,Solidity\n";

// Create the files and write the headers NOW
File.saveString(summaryHeader, summaryPath);
File.saveString(SGdetailedHeader, SGdetailedPath);
File.saveString(nucleiHeader, nucleiDetailedPath);
File.saveString(cellHeader, cellDetailedPath);
File.saveString(auxHeader, auxDetailedPath);
print("Output files initialized.");
print("Summary: " + summaryPath);

// -----------------------------------------------------------
// 3. BEGIN FOR LOOP AND PREPARE IMAGES
// -----------------------------------------------------------
for (i = 0; i < list.length; i++) {
    filename = list[i];
    
// A. Skip non-image files (add more extensions if needed)
if (!endsWith(filename, ".czi") && !endsWith(filename, ".tif") && !endsWith(filename, ".tiff")) {
    continue;
}
    
// B. Open image using Bio-Formats Importer Plugin
if (endsWith(filename, ".czi")) {
    run("Bio-Formats Importer", "open=[" + inputDir + File.separator + filename + "] autoscale color_mode=Composite view=Hyperstack stack_order=XYCZT series_1");

} else {
    open(inputDir + filename);
}

title = getTitle();

// C. Declare image variables
var width = 0;
var height = 0;
var nChannels = 0;
var nSlice = 0;
var nFrames = 0;

// D. Get dimensions of the current image
getDimensions(width, height, nChannels, nSlice, nFrames);

// D1. Now you can safely check slices or other dims
// For epifluorescence images, this "if" statement should not run
if (nSlice > 1) {
    run("Z Project...", "projection=[Max Intensity]");
    close(title);  // Close original hyperstack
    title = getTitle(); // New max projection window
}

// E. Split the image channels and rename for downstream steps
selectWindow(title);
// Define pixel size
getVoxelSize(global_px_w, global_px_h, global_px_d, global_unit);

if (!is("composite")) {
    run("Make Composite");
}

if (nChannels > 1) {
    run("Split Channels");
    selectWindow("C" + nuclei_channel + "-" + title);
    rename("DAPI");
    selectWindow("C" + sg_channel + "-" + title);
    rename("SG_Channel");
if (analyze_aux) {
	if (aux_channel == sg_channel) {
        selectWindow("SG_Channel");
        run("Duplicate...", "title=Aux_Channel_Image");
    } else {
    selectWindow("C" + aux_channel + "-" + title);
    rename("Aux_Channel_Image");
    }
}

} else {
    print("Image " + title + " is not multichannel; skipping this file.");
    close();
    continue;
}

// -----------------------------------------------------------
// 4. ANALYZE NUCLEI USING STARDIST (Net 1)
// -----------------------------------------------------------
selectWindow("DAPI");

// A. Safety Check: Is the image empty?
// If the image is pure black, StarDist will crash.
getStatistics(area, mean, min, max, std, histogram);

if (max == 0) {
    print("WARNING: Image " + filename + " is empty. Skipping nuclei.");
    nuclei_count = 0;
    avg_nucleus_area = 0;
    avg_nucleus_feret = 0;
    
	// Create blank masks to prevent errors downstream
	newImage("Nuclei_White", "8-bit black", width, height, 1);
	newImage("DAPI_blur", "8-bit black", width, height, 1);

} else {
// B. Prepare Image
// Duplicate to keep original image unchanged
run("Duplicate...", "title=DAPI_SD");
    
// C. Run StarDist
run("Command From Macro", "command=[de.csbdresden.stardist.StarDist2D], args=['input':'DAPI_SD', 'modelChoice':'Versatile (fluorescent nuclei)', 'normalizeInput':'true', 'percentileBottom':'1.0', 'percentileTop':'99.8', 'probThresh':'0.72', 'nmsThresh':'0.3', 'outputType':'Both', 'nTiles':'1', 'excludeBoundary':'2', 'roiPosition':'Automatic', 'verbose':'false', 'showCsbdeepProgress':'false', 'showProbAndDist':'false'], process=[false]");

// -----------------------------------------------------------
// 4a. ANALYZE NUCLEI (STARDIST OUTPUT) IN IMAGEJ
// -----------------------------------------------------------
nuclei_count = roiManager("count");

// A. Define output variables for Summary Table
avg_nucleus_area = 0;
avg_nucleus_feret = 0;

// B. Save Nuclei ROIs for later (Essential for % Positive Loop)
nuclei_roi_path = getDirectory("temp") + "temp_nuclei_rois.zip";
if (nuclei_count > 0) {
    roiManager("Save", nuclei_roi_path);
}

// C. Measure Nucleus Area, Diameter
if (nuclei_count > 0) {
	// 1. Setup Measurement Environment
    selectWindow("DAPI"); 
    getPixelSize(unit, pw, ph); 
    pixelArea_um2 = pw * ph;

    // 2. Set the full suite of measurements (Same as SGs)
    run("Set Measurements...", "area mean standard modal min centroid center perimeter bounding fit shape feret's integrated median skewness kurtosis area_fraction stack redirect=None decimal=3");
    run("Clear Results");
    
    // 3. Measure All Nuclei
    roiManager("Deselect");
    roiManager("Measure");
    
    // 4. Process Results
    total_nuc_area = 0;
    total_nuc_feret = 0;
    this_image_nuclei_data = ""; // String builder for CSV
    
    // 5. Define the list of columns to extract (Must match header)
    headings = newArray("Area", "Mean", "StdDev", "Mode", "Min", "Max", "X", "Y", "XM", "YM", "Perim.", "BX", "BY", "Width", "Height", "Major", "Minor", "Angle", "Circ.", "Feret", "IntDen", "Median", "Skew", "Kurt", "%Area", "RawIntDen", "Slice", "FeretX", "FeretY", "FeretAngle", "MinFeret", "AR", "Round", "Solidity");

	// 6. Begin for loop to measure every nucleus ROI (region of interest)
    for (k = 0; k < nResults; k++) {
        // i. Collect data for summary averages
        val_Area = getResult("Area", k); 
        val_Feret = getResult("Feret", k); 
        
        // ii. Assign area, diameter (feret) measurements to each nucleus
        total_nuc_area += val_Area;
        total_nuc_feret += val_Feret;
        
        // iii. Build detailed csv line
        // Collect data for each nucleus and store in RAM
        lineStr = filename + ",Nuc-" + (k+1);
        for (col = 0; col < headings.length; col++) {
             val = getResult(headings[col], k);
             lineStr = lineStr + "," + val;
        }
        this_image_nuclei_data += lineStr + "\n";
    }
    
    // 7. Calculate final averages
    avg_nucleus_area = total_nuc_area / nuclei_count;
    avg_nucleus_feret = total_nuc_feret / nuclei_count;
    
    // 8. Append; store nucleus data in disk after every image
    if (lengthOf(this_image_nuclei_data) > 0) {
        // Trim last newline
        this_image_nuclei_data = substring(this_image_nuclei_data, 0, lengthOf(this_image_nuclei_data) - 1);
        File.append(this_image_nuclei_data, nucleiDetailedPath);
    }
    
    run("Clear Results");
}

// D. Make Nuclei Mask
selectWindow("DAPI_SD");
newImage("Nuclei_White", "8-bit black", width, height, 1);
selectWindow("Nuclei_White");
setForegroundColor(255, 255, 255);
// Fill from the StarDist ROIs (which are currently in the Manager)
roiManager("Deselect");
roiManager("Fill"); 
roiManager("Reset");

// -----------------------------------------------------------
// 5. FIND CELL BOUNDARIES (Dual Engine: Tri-Net vs Dual-Net)
// -----------------------------------------------------------
avg_cyto_area = "Not Available in Dual-Net without LabKit Classifier";
if (startsWith(run_mode, "Tri-Net")) {
// =======================================================
// OPTION A: TRI-NET (GPU / CPSAM)
// =======================================================
// A. Prepare Image for Cellpose (DAPI + SG_Channel)
selectWindow("DAPI");
run("Duplicate...", "title=DAPI_CP");
selectWindow("SG_Channel");
run("Duplicate...", "title=SG_Channel_CP");
run("Merge Channels...", "c1=DAPI_CP c2=SG_Channel_CP create");
rename("Cellpose_Input");

// B. Run Cellpose
print("\nSending " + title + " to Cellpose (GPU)...");
// Note: Ensure your model path is correct in the line below
// KEEP THIS HERE IN CASE IT BREAKS: CPSAM_model_path = "[C:\\Users\\g\\Documents\\Smaldino Lab 12-1-25\\Immunofluorescence\\2025_11_17_NPC-C9-70_250uM_CONTAMINATED\\CPSAM Training Images\\models\\2025_12_13_CPSAM_Find_Cyto_w_G3BP1]";
//run("Cellpose SAM...", "env_path=C:\\Users\\g\\miniforge3\\envs\\cellpose env_type=venv model= model_path=" + CPSAM_model_path + " diameter=60.0 additional_flags=[--use_gpu, --augment, --verbose, --cellprob_threshold=-1.0, --flow_threshold=1.0]");
// ---------------------------------------------------
// PATH B: CELLPOSE (Detailed ROI Measurement)
// ---------------------------------------------------

// 1. Run Cellpose (Output is a Label Image, not a mask)
// We use env_type=venv (assuming you fixed the activation script as discussed)
// We REMOVED the "Convert to Mask" steps so we can keep the IDs.
run("Cellpose SAM...", 
    "env_path=" + cellpose_env_path + 
    " env_type=venv" + 
    " model= model_path=" + CPSAM_model_path + 
    " diameter=60.0" + 
    " additional_flags=[--use_gpu, --augment, --verbose, --cellprob_threshold=-1.0, --flow_threshold=1.0]"
);
run("Collect Garbage");
setBatchMode(batch_logic);

// 2. Process the Output
selectWindow("Cellpose_Input-cellpose");
rename("Cellpose_Raw_Labels");

// --- CRITICAL FIX: PREVENT SCALING ---
// This tells ImageJ: "Keep value 1 as 1. Do not stretch it to 3000."
setOption("ScaleConversions", false);
run("16-bit"); 
// -------------------------------------

// 3. Apply the "Leash" (Grounded Logic)
selectWindow("Nuclei_White"); 
run("Duplicate...", "title=Nuclei_Leash");
run("Maximum...", "radius=75"); 
setThreshold(1, 255);
run("Create Selection");

selectWindow("Cellpose_Raw_Labels");
run("Restore Selection");
setBackgroundColor(0, 0, 0); // Ensure 'Clear' makes pixels 0 (Black)
run("Clear Outside"); 
run("Select None");
if (isOpen("Nuclei_Leash")) { selectWindow("Nuclei_Leash"); close(); }

// 4. Loop Through Labels to Create ROIs
roiManager("Reset"); 
selectWindow("Cellpose_Raw_Labels");

// A. Get the Max ID *before* we turn on 'Limit to Threshold'
run("Set Measurements...", "min redirect=None decimal=3");
getStatistics(area, mean, min, maxID);


// B. Enable 'limit' for the loop
run("Set Measurements...", "area mean centroid center perimeter bounding fit shape feret's integrated median skewness kurtosis area_fraction limit display redirect=None decimal=3");

// Loop from 1 to the highest ID found
for (t = 1; t <= maxID; t++) {
    setThreshold(t, t); 
    
    // Check if pixels exist (Limit is ON, so this checks only thresholded pixels)
    getStatistics(area); 
    
    // Only select if valid pixels remain
    if (area > 0) {
        run("Create Selection");
        
        if (selectionType() != -1) {
            roiManager("Add");
            roiManager("Select", roiManager("count")-1);
            roiManager("Rename", "Cell_Boundary_" + t);
        }
    }
}
resetThreshold();

// Reset measurements for later
run("Set Measurements...", "area mean min centroid center perimeter bounding fit shape feret's integrated median skewness kurtosis area_fraction display redirect=None decimal=3");

// 5. Measure & Append to Master CSV
if (roiManager("count") > 0) {
    selectWindow("SG_Channel"); 
    
    // CRITICAL FIX: Deselect everything so "Measure" sees ALL cells
    roiManager("Deselect"); 
    
    // UPDATE: Removed "limit". 
    // This allows Geometric stats (Solidity, AR, Feret) to calculate correctly.
    run("Set Measurements...", "area mean standard modal min centroid center perimeter bounding fit shape feret's integrated median skewness kurtosis area_fraction display redirect=None decimal=3");
    
    // Measure all ROIs at once
    roiManager("Measure"); 
    
    // Define Headers
    headings = newArray("Area", "Mean", "StdDev", "Mode", "Min", "Max", "X", "Y", "XM", "YM", "Perim.", "BX", "BY", "Width", "Height", "Major", "Minor", "Angle", "Circ.", "Feret", "IntDen", "Median", "Skew", "Kurt", "%Area", "RawIntDen", "Slice", "FeretX", "FeretY", "FeretAngle", "MinFeret", "AR", "Round", "Solidity");

    total_cyto_area = 0;
    this_image_cell_data = ""; 

    // Loop through the Results Table
    for (k = 0; k < nResults; k++) {
        
        // i. Collect data for summary averages
        val_Area = getResult("Area", k); 
        total_cyto_area = total_cyto_area + val_Area;

        // ii. Build detailed CSV line
        lineStr = title + ",Cell-" + (k+1); 

        for (col = 0; col < headings.length; col++) {
             // Handle "Slice" edge case
             if (headings[col] == "Slice") {
                 val = getResult("Slice", k);
                 if (isNaN(val)) { val = 1; }
             } else {
                 val = getResult(headings[col], k);
             }
             lineStr = lineStr + "," + val;
        }
        this_image_cell_data = this_image_cell_data + lineStr + "\n";
    }

    // iii. Append to Master File
    if (lengthOf(this_image_cell_data) > 0) {
        this_image_cell_data = substring(this_image_cell_data, 0, lengthOf(this_image_cell_data) - 1);
        File.append(this_image_cell_data, cellDetailedPath);
    }

    // iv. Calculate Average
    avg_cyto_area = total_cyto_area / nResults;
    
    // Clean up
    run("Clear Results");

} else {
    avg_cyto_area = 0;
}

// 6. Create "Cell_Territories_2" Mask (Final "Brute Force" Fix)
selectWindow("Cellpose_Raw_Labels");
run("Select None"); 
roiManager("Deselect");
run("Duplicate...", "title=Cell_Territories_2");
run("8-bit"); 
run("Select All");
setBackgroundColor(0, 0, 0);
run("Clear"); 
run("Select None");

// Fill in the ROIs
count = roiManager("count");
if (count > 0) {
    // 1. Build list of all ROIs
    all_rois = newArray(count);
    for (cb = 0; cb < count; cb++) {
        all_rois[cb] = cb;
    }
    
    // 2. Select them all
    roiManager("Select", all_rois);
    
    // 3. Fill with White
    setForegroundColor(255, 255, 255);
    roiManager("Fill");
    
    // 4. Cleanup
    roiManager("Deselect");
    run("Select None");
}

// Convert to Mask
setThreshold(1, 255);
run("Convert to Mask"); 
run("Duplicate...", "title=Cell_Territories_Grounded");
run("Duplicate...", "title=Cell_Territories_Grounded_Aux"); 

} else {

// =======================================================
// OPTION B: DUAL-NET (CPU) - SMART HYBRID MODE
// =======================================================
	// ---------------------------------------------------
    // PATH A: LABKIT DETECTED (Medium Accuracy)
    // ---------------------------------------------------
    // If this file doesn't exist, it auto-reverts to the simple Voronoi method.
	max_grow_dist = 75; 
	maxID = "Not Available in Dual-Net";

	if (File.exists(classifier_path_cyto_area)) {
    // 1. Prepare Image
    selectWindow("SG_Channel");
    run("Duplicate...", "title=SG_Channel_Cyto_Seg");
    
    // 2. Run LabKit
    run("Segment Image With Labkit", "input=SG_Channel_Cyto_Seg segmenter_file=[" + classifier_path_cyto_area + "] use_gpu=false");
    setBatchMode(batch_logic);
    
    // 3. Process LabKit Output
    setThreshold(3, 3);
    run("Convert to Mask");
    run("Fill Holes");
    rename("LabKit_Raw"); 
    
    // 4. Clean Up (Fixing the "Show=Masks" bug)
    // "show=Masks" creates a NEW window. We must grab it.
    run("Analyze Particles...", "size=50-Infinity show=Masks"); 
    rename("LabKit_Cleaned"); 
    run("Invert LUT");
    
    // 5. Grounded Mask (No Voronoi Lines)
    // Used for global stats. Allows cells to touch if LabKit says so.
    
    selectWindow("Nuclei_White");
    run("Duplicate...", "title=Nuclei_Exp");
    run("Maximum...", "radius=" + max_grow_dist);
    run("Duplicate...", "title=Nuclei_Exp_2");
    imageCalculator("AND create", "LabKit_Cleaned", "Nuclei_Exp");
    run("Convert to Mask");
    rename("Cell_Territories_Grounded");
    run("Duplicate...", "title=Cell_Territories_Grounded_Aux");

    // 6. Separated Mask (With Voronoi Lines)
    selectWindow("Nuclei_White");
    run("Duplicate...", "title=Voronoi_Map");
    run("Voronoi"); 
    setThreshold(1, 255); 
    run("Convert to Mask"); 
    run("Invert"); 
    imageCalculator("AND create", "LabKit_Cleaned", "Voronoi_Map");
    rename("Cell_Territories_2_A");
    imageCalculator("AND create", "Cell_Territories_2_A", "Nuclei_Exp_2");
    rename("Cell_Territories_2"); 

    // 7. Measurements 
    // We measure the Grounded mask (Total Area) to avoid under-counting pixels on the lines.
    selectWindow("SG_Channel");
    getVoxelSize(px_w, px_h, px_d, unit);
    selectWindow("Cell_Territories_Grounded");
    setVoxelSize(px_w, px_h, px_d, unit);
    
    setThreshold(1, 255);
    run("Set Measurements...", "area limit display redirect=None decimal=3");
    run("Select All");
    run("Measure");
    
    total_cyto_area = getResult("Area", nResults-1); 
    run("Clear Results");
    run("Select None");
    resetThreshold();
    
    if (nuclei_count > 0) {
         avg_cyto_area = total_cyto_area / nuclei_count;
    } else {
         avg_cyto_area = 0;
    }
        
        run("Select None");
        resetThreshold();
        
    // ---------------------------------------------------
    // PATH B: FALLBACK (Geometric Estimation)
    // ---------------------------------------------------
    } else {
        print(">> Classifier NOT found. Using Geometric Estimation...");
        
        // Define cell territories as maximum masks (circles around nuclei)
        selectWindow("Nuclei_White");
        run("Duplicate...", "title=Cell_Territories");
        run("Maximum...", "radius=" + max_grow_dist);
        selectWindow("Cell_Territories");
		run("Duplicate...", "title=Cell_Territories_2");
		selectWindow("Cell_Territories");
		rename("Cell_Territories_Grounded");
		selectWindow("Cell_Territories_Grounded");
		run("Duplicate...", "title=Cell_Territories_Grounded_Aux");
    }
}

run("Collect Garbage");
setBatchMode(batch_logic);
// -----------------------------------------------------------
// 6. ANALYZE STRESS GRANULES USING AUTOMATIC THRESHOLDING
// -----------------------------------------------------------
// A. Make copies for later
selectWindow("SG_Channel");
run("Duplicate...", "title=SG_Channel_%");
selectWindow("SG_Channel");
run("Duplicate...", "title=SG_Channel_copy");
selectWindow("SG_Channel_copy");

// B. Preprocess to suppress aggregates
run("Subtract Background...", "rolling=1.75");
//THIS SETTING REDUCES BACKGROUND AND ENHANCES SG DETECTION.

run("Enhance Contrast", "saturated=0.095 normalize"); 
//THIS SETTING PRODUCES BETTER SG DETECTION, BUT ALSO FINDS CELL BOUNDARIES ABOVE 0.15. MAKES VALIDATION HARD.
//THE 0.095 VALUE HAS BEEN OPTIMIZED FOR NPC SG ANALYSIS. OPTIMIZE FOR CELL TYPE.
//0.095 SUBTRACTS 0.0425% OF HIGHEST AND LOWEST PIXEL INTENSITIES.
//IN GENERAL, DECREASING THIS WILL DECREASE SG DETECTION, INCREASING INCREASES DETECTION.

// C. Auto Threshold to remove background and isolate granules
run("Auto Threshold", "method=MaxEntropy White");
run("Convert to Mask");

// D. Create AND mask so we only count granules inside cells
// In other words, delete any granules that don't overlap with cell boundaries/cytoplasm
imageCalculator("AND create", "SG_Channel_copy", "Cell_Territories_Grounded");
rename("SG_Channel_and"); 

// E. Calibrate measurements for microns, not pixels 
selectWindow("SG_Channel"); // Check original image
getPixelSize(unit, pw, ph);
selectWindow("SG_Channel_and");
run("Set Scale...", "distance=1 known="+pw+" unit="+unit);

// F. Count SGs
roiManager("reset");
setThreshold(255, 255);
run("Analyze Particles...", "size=" + min_sg_size + "-" + max_sg_size + " add");
sg_count = roiManager("count");

	// 1. Ensure measurements will include Area
	run("Set Measurements...", "area centroid integrated redirect=None decimal=3");
	
	// 2. Clear previous results so we know the table is empty
	run("Clear Results");
	
	// 3. Run Analyze Particles so results are written to the Results table
	run("Analyze Particles...", "size=" + min_sg_size + "-" + max_sg_size + " show=Nothing clear");
	
	// 4. Check how many results we have
	if (sg_count == 0) {
	    print("No particles detected (Results table empty).");
	} else {
		
    // 5. Get areas and calculate averages (in pixel^2)
    totalArea_pixels = 0;
    for (j = 0; j < sg_count; j++) {
        totalArea_pixels += getResult("Area", j);
    }

    // 5a. Convert to µm^2 (requires calibrated pixel size)
    getPixelSize(unit, pw, ph); // pw,ph in µm/pixel
    pixelArea_um2 = pw * ph;
    totalArea_um2 = totalArea_pixels * pixelArea_um2;

    // 5b. Average area per SG
    avgArea_um2 = totalArea_um2 / sg_count;
	}

// -----------------------------------------------------------
// 7. UNIFIED MEASUREMENTS FOR SG ANALYSIS
// -----------------------------------------------------------
// A. Initialize Global Variables
totalArea_val = 0;
sumSq_val = 0;
total_intensity_sum = 0;
sum_circ = 0; sum_solid = 0; sum_feret = 0;

// Outputs
avgArea_um2 = 0; sd_um2 = 0; variance_um2 = 0;
intMean = 0; avg_circ = 0; avg_solid = 0; avg_feret = 0;

// Initialize Sorting Variables (Small vs Large)
count_small = 0; count_large = 0;
sum_area_small = 0; sumSq_area_small = 0;
sum_int_small = 0; sum_circ_small = 0; sum_solid_small = 0; sum_feret_small = 0;
sum_area_large = 0; sumSq_area_large = 0;
sum_int_large = 0; sum_circ_large = 0; sum_solid_large = 0; sum_feret_large = 0;

// Averages (Small)
avg_area_small = 0; sd_area_small = 0; var_area_small = 0;
avg_int_small = 0; avg_circ_small = 0; avg_solid_small = 0; avg_feret_small = 0;

// Averages (Large)
avg_area_large = 0; sd_area_large = 0; var_area_large = 0;
avg_int_large = 0; avg_circ_large = 0; avg_solid_large = 0; avg_feret_large = 0;
this_image_detailed_data = "";

// B. Perform Measurements
if (sg_count > 0 && roiManager("count") == sg_count) {
    
    // 1. Get Calibration from Source
    selectWindow("SG_Channel");
    getPixelSize(unit, pw, ph); 
    pixelArea_um2 = pw * ph;

    // 2. Prepare Measurement Image (With Calibration Applied)
    run("Duplicate...", "title=SG_Channel_Raw_Measure");
    selectWindow("SG_Channel_Raw_Measure");
    setVoxelSize(pw, ph, 1, unit); 
    run("Set Measurements...", "area mean standard modal min centroid center perimeter bounding fit shape feret's integrated median skewness kurtosis area_fraction stack redirect=None decimal=3");
    run("Clear Results");
    roiManager("Deselect"); 
    roiManager("Measure");  
    headings = newArray("Area", "Mean", "StdDev", "Mode", "Min", "Max", "X", "Y", "XM", "YM", "Perim.", "BX", "BY", "Width", "Height", "Major", "Minor", "Angle", "Circ.", "Feret", "IntDen", "Median", "Skew", "Kurt", "%Area", "RawIntDen", "Slice", "FeretX", "FeretY", "FeretAngle", "MinFeret", "AR", "Round", "Solidity");

    // 3. Iterate Results
    for (k = 0; k < nResults; k++) {
        // i. Get Raw Values (Calibrated in Microns)
        val_Area    = getResult("Area", k);      
        val_Mean    = getResult("Mean", k);      
        val_RawInt  = getResult("RawIntDen", k); 
        val_Circ    = getResult("Circ.", k);     
        val_Solid   = getResult("Solidity", k);  
        val_Feret   = getResult("Feret", k);     
        val_Area_um = val_Area;
        val_Feret_um = val_Feret; 

        // ii. Global Accumulators
        totalArea_val += val_Area_um;
        sumSq_val     += (val_Area_um * val_Area_um);
        total_intensity_sum += val_Mean;
        sum_circ      += val_Circ;
        sum_solid     += val_Solid;
        sum_feret     += val_Feret_um;

        // iii. Sorting (Small vs Large)
        size_class = "";
        if (val_Area_um < split_point) {
            size_class = "Small";
            count_small++;
            sum_area_small += val_Area_um;
            sumSq_area_small += (val_Area_um * val_Area_um);
            sum_int_small += val_Mean;
            sum_circ_small += val_Circ;
            sum_solid_small += val_Solid;
            sum_feret_small += val_Feret_um;
        } else {
            size_class = "Large";
            count_large++;
            sum_area_large += val_Area_um;
            sumSq_area_large += (val_Area_um * val_Area_um);
            sum_int_large += val_Mean;
            sum_circ_large += val_Circ;
            sum_solid_large += val_Solid;
            sum_feret_large += val_Feret_um;
        }

        // iv. Build the csv file
        lineStr = filename + ",SG-" + (k+1) + "," + size_class;
        for (col = 0; col < headings.length; col++) {
             val = getResult(headings[col], k);
             lineStr = lineStr + "," + val;
        }
        this_image_detailed_data += lineStr + "\n";
    }

// C. Calculate Final Averages (in Microns)
intMean = total_intensity_sum / sg_count;
avg_circ = sum_circ / sg_count;
avg_solid = sum_solid / sg_count;
avg_feret = sum_feret / sg_count;
avgArea_um2 = totalArea_val / sg_count;
    
    // 1. Standard Deviation (Microns), Variance = (SumSquares / N) - (Mean * Mean)
    variance_um2 = (sumSq_val / sg_count) - (avgArea_um2 * avgArea_um2);
    if (variance_um2 < 0) variance_um2 = 0;
    sd_um2 = sqrt(variance_um2);
    
    // 2. SMALL SG Stats
    if (count_small > 0) {
        avg_area_small = sum_area_small / count_small;
        avg_int_small = sum_int_small / count_small;
        avg_circ_small = sum_circ_small / count_small;
        avg_solid_small = sum_solid_small / count_small;
        avg_feret_small = sum_feret_small / count_small;
        
        var_area_small = (sumSq_area_small / count_small) - (avg_area_small * avg_area_small);
        if (var_area_small < 0) var_area_small = 0;
        sd_area_small = sqrt(var_area_small);
    }

    // 3. LARGE SG Stats
    if (count_large > 0) {
        avg_area_large = sum_area_large / count_large;
        avg_int_large = sum_int_large / count_large;
        avg_circ_large = sum_circ_large / count_large;
        avg_solid_large = sum_solid_large / count_large;
        avg_feret_large = sum_feret_large / count_large;

        var_area_large = (sumSq_area_large / count_large) - (avg_area_large * avg_area_large);
        if (var_area_large < 0) var_area_large = 0;
        sd_area_large = sqrt(var_area_large);
    }
}
// -----------------------------------------------------------
// 8. PERCENT POSITIVE ANALYSIS USING LABKIT (Net 3)
// -----------------------------------------------------------
// This block calculates SG+ cells completely separately from the SG Counting above.
// It generates its own masks and variables to ensure no conflicts.
// A. Prepare Cell Boundaries from Cellpose
pct_min_intensity = 0;  // Intensity Threshold (I have this at 0 to eliminate intensity gating for now)
pct_min_area_um = 0.2;    // Total SG area (um2) required to be "Positive"
percent_positive = 0; 
pct_pos_count = 0;

// 1. Create the "Seeds" Image (Single Dots at Centroids)
newImage("Pct_Seeds", "8-bit black", width, height, 1);
selectWindow("Pct_Seeds"); 

// 2. Reload Nuclei ROIs (to act as the "Separators")
roiManager("Reset");
nuclei_roi_path = getDirectory("temp") + "temp_nuclei_rois.zip";
if (File.exists(nuclei_roi_path)) {
    roiManager("Open", nuclei_roi_path);
}
nuclei_count_check = roiManager("count"); 

// 3. Loop through Nuclei ROIs to paint dots
if (nuclei_count_check > 0) {
    for (k = 0; k < nuclei_count_check; k++) {
        roiManager("Select", k);
        // Calculate center of the bounding box
        getSelectionBounds(x_r, y_r, w_r, h_r);
        x_center = x_r + (w_r / 2);
        y_center = y_r + (h_r / 2);
        // Draw a single white pixel
        setPixel(x_center, y_center, 255);
    }
    roiManager("Deselect");
    run("Select None");
}

// 4. Generate whole-image Voronoi from dots
selectWindow("Pct_Seeds");
run("Duplicate...", "title=Pct_Voronoi");
run("Voronoi");
setThreshold(1, 255);
run("Convert to Mask");
run("Invert");
run("Duplicate...", "title=Pct_Voronoi_2"); 

// 5. Generate Constraint from Filled Shapes
newImage("Pct_Shapes", "8-bit black", width, height, 1);
selectWindow("Pct_Shapes");
setForegroundColor(255, 255, 255);
if (nuclei_count_check > 0) {
    roiManager("Deselect");
    roiManager("Fill");
}

selectWindow("Pct_Shapes");
run("Duplicate...", "title=Pct_Limit");
run("Maximum...", "radius=75"); //waitForUser("Maximum from seed"); // Grow 100px from the Nucleus edge

// 6. Combine (Blobs Around Cells)
imageCalculator("AND create", "Pct_Voronoi", "Pct_Limit");
rename("Cell_Territories_V"); //waitForUser("Combined");

// 7. AND Mask the Cellpose Territories from Step 5 and Cell Blobs 
selectWindow("Cell_Territories_Grounded"); 
run("8-bit");
setThreshold(1, 255);
run("Convert to Mask");
rename("Pct_Cellpose_Mask"); 
imageCalculator("AND create", "Cell_Territories_V", "Pct_Cellpose_Mask");
rename("Cell_Territories_2_%"); 

// B. Segment Image Using LabKit Classifier 
    
// 1. SAFETY CHECK: Does the file exist?
labkit_success = false;
if (File.exists(classifier_path_SG_pct)) {
    selectWindow("SG_Channel_%");
    
// 2. Inject that variable into the run string
run("Segment Image With Labkit", "input=SG_Channel_% segmenter_file=[" + classifier_path_SG_pct + "] use_gpu=false");

    if (isOpen("segmentation of SG_Channel_%")) {
        selectWindow("segmentation of SG_Channel_%");
        rename("LabKit_Map");
        } else if (isOpen("segmentation")) {
        selectWindow("segmentation");
        rename("LabKit_Map");
    }
        
        // 3. Extract Class (SGs are 4, 4)
        if (isOpen("LabKit_Map")) {
        selectWindow("LabKit_Map");
        setThreshold(4, 4);  
        run("Convert to Mask"); 
        rename("Pct_Structure_Mask");
        labkit_success = true;
        
        // 4. Fix Visuals if needed
        if (is("Inverted LUT")) run("Invert LUT");
        rename("Pct_Structure_Mask");
        labkit_success = true; 
    } else {
        print("ERROR: LabKit ran but produced no output window.");
    }

} else {
    print("CRITICAL ERROR: Classifier file not found at: " + classifier_path_SG_pct);
    print("Skipping % Positive calculation for this image.");
}

// C. Remove Aggregates or Noise Using Logic Gating
if (labkit_success) {
    
    // 1. Run Intensity Gate (currently set to 0; doesn't do anything)
    selectWindow("SG_Channel_%");
    run("Duplicate...", "title=Pct_Intensity_Mask");
    setThreshold(pct_min_intensity, 65535);
    run("Convert to Mask");
    
    // 2. Combine (remove granules that are too dim)
    imageCalculator("AND create", "Pct_Structure_Mask", "Pct_Intensity_Mask");
    rename("SG_Channel_Verified_PreFilter"); 
    
    // 3. Size Filter
    selectWindow("SG_Channel_Verified_PreFilter");
    run("Analyze Particles...", "size=" + pct_min_area_um + "-Infinity show=Masks"); 
    rename("SG_Channel_%_Calc_Final");
    run("Invert LUT");
        
} else {
    // Fallback if LabKit failed/missing: Create an empty mask so the code doesn't crash
    pct_pos_count = NaN;
    pct_nCells = NaN;
    newImage("SG_Channel_%_Calc_Final", "8-bit black", width, height, 1);
    print("Using empty mask for % Positive due to missing classifier.");
}

// D. For Loop to Classify Individual Cells as SG+/-
// We use the Voronoi Zones (Containers) to check each cell.

if (labkit_success) {
    pct_pos_count = 0;
    
// 1. Define the "Containers" (Voronoi Tiles)
// We use the pre-made Voronoi map from Block A (Pct_Voronoi_2)
roiManager("Reset");
selectWindow("Pct_Voronoi_2");

// Ensure we are selecting the White Zones (Cell Regions)
setThreshold(1, 255); 
run("Analyze Particles...", "size=0-Infinity add"); 

pct_nCells = roiManager("count"); // This matches your Nucleus count exactly

// 2. Define the "Contents" (SGs Restricted to Cell Boundaries)
// "SG_Channel_%_Calc_Final" has the SGs.
// "Cell_Territories_2" has the actual Cytoplasm shapes.
// We AND them so any SGs floating in the background (outside cytoplasm) are deleted.
imageCalculator("AND create", "SG_Channel_%_Calc_Final", "Cell_Territories_2");
rename("SG_Bounded_Checking");

// 3. Prepare for Measurement
selectWindow("SG_Channel_%"); 
getPixelSize(unit, pw, ph);
pct_pixelArea = pw * ph;

// We measure the BOUNDED image
selectWindow("SG_Bounded_Checking"); 
run("Set Measurements...", "integrated redirect=None decimal=3"); 

// 4. Run the Loop
for (p = 0; p < pct_nCells; p++) {
    roiManager("Select", p); // Select Voronoi Tile #p
    
    // Measure SGs inside this Tile
    // (Note: Because we measure "SG_Bounded_Checking", we only count SGs 
    // that are BOTH inside this Voronoi Tile AND inside the Cytoplasm mask)
    pct_raw_int = getValue("RawIntDen");
    pct_white_pixels = pct_raw_int / 255;
    pct_sg_area_um = pct_white_pixels * pct_pixelArea;
    
    // LOGIC GATE: Is this cell Positive?
    if (pct_sg_area_um > pct_min_area_um) {
        pct_pos_count++;
    }
}

// Cleanup
if (isOpen("SG_Bounded_Checking")) { selectWindow("SG_Bounded_Checking"); close(); }
}

// E. Final Calculations
// 1. Check for failure flags (NaN) first
if (isNaN(pct_nCells) || isNaN(pct_pos_count)) {
    percent_positive = NaN;
} 
// 2. If valid cells exist, calculate percentage
else if (pct_nCells > 0) {
    percent_positive = (pct_pos_count / pct_nCells) * 100;
} 
// 3. If valid run but 0 cells found (Avoid division by zero)
else {
    percent_positive = 0;
}

//roiManager("Reset");

// E. Cleanup: Delete temporary nucleus ROI file
//roiManager("Reset");
ok = File.delete(nuclei_roi_path); 

// -----------------------------------------------------------
// 9. AUX INTENSITY MEASUREMENT
// -----------------------------------------------------------
// This block measures the intensity of Auxiliary channel (user-defined) inside the Cellpose territories.
// A. Initialize Variables (Default to NaN)
// If the user selects "None", these remain NaN and will appear empty in Excel.
aux_avg_mean = NaN;      // Output: Average Brightness (Intensity)
aux_avg_intden = NaN;    // Output: Average Total Fluorescence per Cell

// B. Measurement Logic (Per-Cell & Summary)
if (analyze_aux) {

	// 1. PREP: Reset and Re-Populate ROI Manager with Individual Cells
    // We need to clear the Voronoi map and get back to individual cell outlines
    roiManager("reset"); 
    
    // Check if your specific binary mask window exists
    if (isOpen("Cell_Territories_2_%")) {
        selectWindow("Cell_Territories_2_%");
        
        // Run Particle Analyzer to find individual cells again
        // "Add to Manager" is the critical part here
        // We use min-size 100 (or whatever your limit is) to avoid noise
        run("Analyze Particles...", "size=0-Infinity show=Nothing add");
    }

    // 2. Safety Check: Do we have cells? Is the image open?
    if (roiManager("count") > 0 && isOpen("Aux_Channel_Image")) {

        selectWindow("Aux_Channel_Image");
        run("Select None"); // Safety clear
        roiManager("Deselect");
        
        // Clear any previous results to avoid mixing data
        run("Clear Results");

        // 3. Set Measurements 
        // (Ensuring all keys needed for your CSV are selected)
        run("Set Measurements...", "area mean standard modal min centroid center perimeter bounding fit shape feret's integrated median skewness kurtosis area_fraction display redirect=None decimal=3");

        // 4. Measure all ROIs at once
        // This populates the Results Table with one row per cell
        roiManager("Measure");

        // 5. Define Headers to match your CSV structure
        // These MUST match the order in 'auxHeader' from your previous code
        headings = newArray("Area", "Mean", "StdDev", "Mode", "Min", "Max", "X", "Y", "XM", "YM", "Perim.", "BX", "BY", "Width", "Height", "Major", "Minor", "Angle", "Circ.", "Feret", "IntDen", "Median", "Skew", "Kurt", "%Area", "RawIntDen", "Slice", "FeretX", "FeretY", "FeretAngle", "MinFeret", "AR", "Round", "Solidity");

        // Initialize accumulators
        total_aux_mean = 0;
        total_aux_intden = 0;
        this_image_aux_data = "";

        // 6. Loop through the Results Table
        // WARNING: distinct variable 'aux_row' used to prevent conflict
        for (aux_row = 0; aux_row < nResults; aux_row++) {

            // i. Collect data for summary averages (Mean and IntDen)
            val_Mean = getResult("Mean", aux_row);
            val_IntDen = getResult("IntDen", aux_row);
            
            total_aux_mean = total_aux_mean + val_Mean;
            total_aux_intden = total_aux_intden + val_IntDen;

            // ii. Build detailed CSV line
            // Start with Filename and Cell_ID
            lineStr = title + "," + (aux_row + 1); 

            // Loop through columns to build the comma-separated line
            for (col = 0; col < headings.length; col++) {
                 // Handle "Slice" edge case (if undefined, default to 1)
                 if (headings[col] == "Slice") {
                     val = getResult("Slice", aux_row);
                     if (isNaN(val)) { val = 1; }
                 } else {
                     val = getResult(headings[col], aux_row);
                 }
                 lineStr = lineStr + "," + val;
            }
            this_image_aux_data = this_image_aux_data + lineStr + "\n";
        }

        // 7. Append to Master File
        // Remove the trailing newline from the very last row before appending
        if (lengthOf(this_image_aux_data) > 0) {
            this_image_aux_data = substring(this_image_aux_data, 0, lengthOf(this_image_aux_data) - 1);
            File.append(this_image_aux_data, auxDetailedPath);
        }

        // 8. Calculate Global Averages for the Summary CSV
        if (nResults > 0) {
            aux_avg_mean   = total_aux_mean / nResults;
            aux_avg_intden = total_aux_intden / nResults;
        } else {
            aux_avg_mean = 0;
            aux_avg_intden = 0;
        }

        // Clean up results table for the next image
        run("Clear Results");

    } else {
        // Fallback if cells are missing (but Aux was requested)
        print("Warning: Aux requested but no cells detected or image missing.");
        aux_avg_intden = 0;
        aux_avg_mean = 0;
    }
}
}
// -----------------------------------------------------------
// 10. FINALIZE IMAGE DATA
// -----------------------------------------------------------
// A. Confirm nuclei are present
if (nuclei_count > 0) {
    sg_per_cell = sg_count / nuclei_count;
    small_per_cell = count_small / nuclei_count;
    large_per_cell = count_large / nuclei_count;
} else {
    sg_per_cell = 0;
    small_per_cell = 0;
    large_per_cell = 0;
}

// B. Save SG data to files after each image
if (lengthOf(this_image_detailed_data) > 0) {
    this_image_detailed_data = substring(this_image_detailed_data, 0, lengthOf(this_image_detailed_data) - 1);
    
    // Append to the file
    File.append(this_image_detailed_data, SGdetailedPath);
}
// C. Save summary data to files after each image
summaryLine = filename + "," + pipeline + "," + nuclei_count + "," + avg_nucleus_area + "," + avg_cyto_area + ","
+ avg_nucleus_feret + "," + pct_pos_count + "," + percent_positive + ","+ sg_count + "," + count_small + "," + count_large 
+ "," + sg_per_cell + "," + small_per_cell + "," + large_per_cell + "," 
+ totalArea_um2 + "," + avgArea_um2 + "," + avg_area_small + "," + avg_area_large 
+ "," + sd_um2 + "," + sd_area_small + "," + sd_area_large + "," + variance_um2 
+ "," + var_area_small + "," + var_area_large + "," + intMean + "," 
+ avg_int_small + "," + avg_int_large + "," + avg_circ + "," + avg_circ_small 
+ "," + avg_circ_large + "," + avg_solid + "," + avg_solid_small + "," 
+ avg_solid_large + "," + avg_feret + "," + avg_feret_small + "," 
+ avg_feret_large;
if (analyze_aux) {
    summaryLine = summaryLine + "," + aux_avg_mean + "," + aux_avg_intden;
}
File.append(summaryLine, summaryPath); 

// -----------------------------------------------------------
// 11. PRINT SUMMARY DATA IN LOG AND PREPARE FOR NEXT IMAGE
// -----------------------------------------------------------
print("\n"); 
print("=== Results for: " + filename + " ===");
print("Cells (nuclei): " + nuclei_count);
							print("Cell Areas Found (Cellpose): " + maxID);
						print("Avg Nucleus Area: " + avg_nucleus_area);
print("Stress Granules: " + sg_count);
					print("SG Positive Cells (%): " + percent_positive);
print("SGs per Cell: " + sg_per_cell);
    print("Total area (pixels²): " + totalArea_pixels);
    print("Total area (µm²): " + totalArea_um2);
    print("Average SG area (µm²): " + avgArea_um2);
	    print("SD (µm²): " + sd_um2);
	    print("Variance (µm²): " + variance_um2);
			print("Average Intensity of SGs (mean pixel value): " + intMean);
				print("SMALL (<" + split_point + "um): " + count_small + " (" + small_per_cell + "/cell)");
				print("Size: " + avg_area_small + " (SD: " + sd_area_small + ")");
				print("Circ: " + avg_circ_small + " | Solid: " + avg_solid_small);
				print("LARGE (>" + split_point + "um): " + count_large + " (" + large_per_cell + "/cell)");
				print("Size: " + avg_area_large + " (SD: " + sd_area_large + ")");
				print("Circ: " + avg_circ_large + " | Solid: " + avg_solid_large);

// Close all images, clear results and ROI manager, and collect garbage (to protect against RAM leaks), 
// refresh false batch mode so Cellpose works
run("Close All");
run("Clear Results");
roiManager("Reset");
run("Collect Garbage"); 
setBatchMode(false);
}

// Done
print("Batch analysis complete.");
