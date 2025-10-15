// ImageJ Macro for Automatic c-Fos Cell Counting
// For 2D TIF fluorescence microscope images with:
// - Flexible channel configuration for c-Fos (red, green, or blue)
// - Optional DAPI analysis
// - Support for multiple ROIs

// Clear any existing results and log
run("Clear Results");
print("\\Clear");
if (isOpen("ROI Manager")) {
    selectWindow("ROI Manager");
    run("Close");
}

// Set up global variables for ROI information
var roiNames = newArray();
var hasImportedROISettings = false;
var roiCount = 0;

// Global variables for channel configuration
var cFosChannel = "red";  // Default: red channel
var dapiChannel = "blue"; // Default: blue channel
var useDAPI = true;       // Default: use DAPI

// Global arrays for batch summary data collection
var allNumbers = newArray(0);
var allRois = newArray(0);
var allFileNames = newArray(0);
var allTotalDapi = newArray(0);
var allCFosCells = newArray(0);
var allROIAreas = newArray(0);
var allCFosDensity = newArray(0);

// Load ROI settings if available
function importROISettings() {
    // Prompt user to select the settings file
    var settingsPath = File.openDialog("Select the ROI Settings File (JSON)");
    
    // Check if user canceled the file selection
    if (settingsPath == "") {
        showMessage("Import Canceled", "Settings import was canceled. Using default settings.");
        return 0;
    }
    
    // Automatically enable multiple ROI analysis if settings are loaded successfully
    multiROI = true;
    
    if (File.exists(settingsPath)) {
        // Read JSON file content
        jsonString = File.openAsString(settingsPath);
        
        // Extract ROI count
        roiCountMatch = indexOf(jsonString, "\"roiCount\":");
        if (roiCountMatch >= 0) {
            startIndex = roiCountMatch + 11; // Length of "roiCount": 
            endIndex = indexOf(jsonString, ",", startIndex);
            if (endIndex < 0) endIndex = indexOf(jsonString, "}", startIndex);
            countStr = substring(jsonString, startIndex, endIndex);
            importedROICount = parseInt(countStr);
            
            // Extract ROI names array
            namesMatch = indexOf(jsonString, "\"roiNames\":");
            if (namesMatch >= 0 && importedROICount > 0) {
                // Find the array
                arrayStart = indexOf(jsonString, "[", namesMatch);
                arrayEnd = indexOf(jsonString, "]", arrayStart);
                if (arrayStart >= 0 && arrayEnd > arrayStart) {
                    // Extract array content
                    arrayContent = substring(jsonString, arrayStart + 1, arrayEnd);
                    // Split by commas and clean up quotes
                    namesList = split(arrayContent, ",");
                    if (namesList.length > 0) {
                        roiNames = newArray(importedROICount);
                        for (i = 0; i < importedROICount && i < namesList.length; i++) {
                            // Clean up quotes, spaces, and line breaks
                            name = namesList[i];
                            // Remove quotes
                            name = replace(name, "\"", "");
                            // Remove all whitespace characters (spaces, tabs, line breaks)
                            name = replace(name, "\\s+", "");
                            // Remove newlines and carriage returns explicitly
                            name = replace(name, "\n", "");
                            name = replace(name, "\r", "");
                            name = replace(name, "\t", "");
                            // Final cleanup of any remaining whitespace
                            name = String.trim(name);
                            
                            roiNames[i] = name;
                        }
                        
                        // Display the imported settings
                        Dialog.create("ROI Settings Imported");
                        Dialog.addMessage("Successfully imported settings for " + importedROICount + " ROIs:", 14, "#191970");
                        
                        // Show the list of imported ROI names without line breaks
                        settingsInfo = "";
                        for (i = 0; i < roiNames.length; i++) {
                            settingsInfo += "ROI #" + (i+1) + ": '" + roiNames[i] + "'\n";
                        }
                        Dialog.addMessage(settingsInfo, 12, "black");
                        Dialog.addCheckbox("Proceed with these settings?", true);
                        Dialog.show();
                        
                        // Check if user wants to proceed with these settings
                        if (!Dialog.getCheckbox()) {
                            return 0;  // User chose not to use these settings
                        }
                        
                        return importedROICount;
                    }
                }
            }
        }
    }
    showMessage("Import Failed", "Could not import ROI settings. Using default settings.");
    return 0;
}

// Export ROI settings
function exportROISettings(roiCount, roiNames) {
    // Get the directory to save the file
    saveDir = getDirectory("Choose a Directory to Save ROI Settings");
    
    if (saveDir != "") {
        // Create a dialog to get the filename
        Dialog.create("Save ROI Settings");
        Dialog.addString("Filename:", "roi_settings.json");
        Dialog.show();
        
        filename = Dialog.getString();
        settingsPath = saveDir + filename;
        
        // Build JSON string
        jsonString = "{\n";
        jsonString = jsonString + "  \"roiCount\": " + roiCount + ",\n";
        jsonString = jsonString + "  \"roiNames\": [\n";
        
        // Add each ROI name
        for (i = 0; i < roiNames.length; i++) {
            jsonString = jsonString + "    \"" + roiNames[i] + "\"";
            if (i < roiNames.length - 1) {
                jsonString = jsonString + ",";
            }
            jsonString = jsonString + "\n";
        }
        
        // Close JSON structure
        jsonString = jsonString + "  ]\n";
        jsonString = jsonString + "}";
        
        // Write JSON to file
        File.saveString(jsonString, settingsPath);
        
        // Show sample template
        Dialog.create("ROI Settings Exported");
        Dialog.addMessage("Successfully exported settings for " + roiCount + " ROIs.", 14, "#191970");
        Dialog.addMessage("Saved to: " + settingsPath, 12, "gray");
        Dialog.addMessage("JSON Template:", 14, "#191970");
        Dialog.addMessage(jsonString, 12, "black");
        Dialog.show();
    }
}

// Function to extract ID and brain region from filename
function extractFileInfo(filename) {
    // Initialize with defaults
    info = newArray(2);
    info[0] = ""; // ID
    info[1] = ""; // Brain region
    
    // Try to parse using standard format like "1477_DRN_17.tif"
    parts = split(filename, "_");
    
    if (parts.length >= 2) {
        // If we have at least 2 parts, use the first as ID and second as brain region
        info[0] = parts[0];
        info[1] = parts[1];
    } else {
        // If we can't parse according to convention, use whole filename without extension as ID
        dotIndex = lastIndexOf(filename, ".");
        if (dotIndex != -1) {
            info[0] = substring(filename, 0, dotIndex);
        } else {
            info[0] = filename;
        }
    }
    
    return info;
}

// Function to extract numeric sequence from filename
function extractSequenceNumber(filename) {
    // Default to empty string
    seqNum = "";
    
    // Try to find a sequence number at the end of the filename
    parts = split(filename, "_");
    if (parts.length > 0) {
        lastPart = parts[parts.length-1];
        // Remove file extension if present
        dotIndex = lastIndexOf(lastPart, ".");
        if (dotIndex != -1) {
            lastPart = substring(lastPart, 0, dotIndex);
        }
        
        // Check if the last part is purely numeric
        if (matches(lastPart, "^[0-9]+$")) {
            seqNum = lastPart;
        }
    }
    
    return seqNum;
}

// Function to save configuration to file
function saveConfiguration(configPath, params) {
    jsonString = "{\n";
    jsonString = jsonString + "  \"cFosChannel\": \"" + params[0] + "\",\n";
    jsonString = jsonString + "  \"useDAPI\": " + params[1] + ",\n";
    jsonString = jsonString + "  \"dapiChannel\": \"" + params[2] + "\",\n";
    jsonString = jsonString + "  \"imageSource\": \"" + params[3] + "\",\n";
    jsonString = jsonString + "  \"multiROI\": " + params[4] + ",\n";
    jsonString = jsonString + "  \"roiCount\": " + params[5] + ",\n";
    jsonString = jsonString + "  \"doImportROI\": " + params[6] + ",\n";
    jsonString = jsonString + "  \"exportROI\": " + params[7] + ",\n";
    jsonString = jsonString + "  \"bgRadius\": " + params[8] + ",\n";
    jsonString = jsonString + "  \"claheBlockSize\": " + params[9] + ",\n";
    jsonString = jsonString + "  \"claheHistBins\": " + params[10] + ",\n";
    jsonString = jsonString + "  \"claheMaxSlope\": " + params[11] + ",\n";
    jsonString = jsonString + "  \"minNucleusSize\": " + params[12] + ",\n";
    jsonString = jsonString + "  \"maxNucleusSize\": " + params[13] + ",\n";
    jsonString = jsonString + "  \"nucleusCircularity\": " + params[14] + ",\n";
    jsonString = jsonString + "  \"thresholdChoice\": \"" + params[15] + "\",\n";
    jsonString = jsonString + "  \"fullyAutomatic\": " + params[16] + ",\n";
    jsonString = jsonString + "  \"minOverlap\": " + params[17] + ",\n";
    jsonString = jsonString + "  \"minCfosSize\": " + params[18] + ",\n";
    jsonString = jsonString + "  \"maxCfosSize\": " + params[19] + ",\n";
    jsonString = jsonString + "  \"cFosCircularity\": " + params[20] + ",\n";
    jsonString = jsonString + "  \"dapiColor\": \"" + params[21] + "\",\n";
    jsonString = jsonString + "  \"useGreenChannel\": " + params[22] + ",\n";
    jsonString = jsonString + "  \"saveOverlay\": " + params[23] + ",\n";
    jsonString = jsonString + "  \"saveROIPosition\": " + params[24] + "\n";
    jsonString = jsonString + "}";
    
    File.saveString(jsonString, configPath);
}

// Function to load configuration from file
function loadConfiguration(configPath) {
    params = newArray(25);
    
    // Set defaults first
    params[0] = "Red";           // cFosChannel
    params[1] = 1;               // useDAPI (1=true)
    params[2] = "Blue";          // dapiChannel
    params[3] = "Directory";     // imageSource
    params[4] = 0;               // multiROI (0=false)
    params[5] = 2;               // roiCount
    params[6] = 0;               // doImportROI
    params[7] = 0;               // exportROI
    params[8] = 100;             // bgRadius
    params[9] = 16;              // claheBlockSize
    params[10] = 256;            // claheHistBins
    params[11] = 2.0;            // claheMaxSlope
    params[12] = 50;             // minNucleusSize
    params[13] = 500;            // maxNucleusSize
    params[14] = 0.5;            // nucleusCircularity
    params[15] = "Manual";       // thresholdChoice
    params[16] = 0;              // fullyAutomatic
    params[17] = 40;             // minOverlap
    params[18] = 30;             // minCfosSize
    params[19] = 250;            // maxCfosSize
    params[20] = 0.4;            // cFosCircularity
    params[21] = "green";        // dapiColor
    params[22] = 1;              // useGreenChannel
    params[23] = 1;              // saveOverlay
    params[24] = 1;              // saveROIPosition
    
    // If config file exists, load values
    if (File.exists(configPath)) {
        jsonString = File.openAsString(configPath);
        
        // Parse each field
        if (indexOf(jsonString, "\"cFosChannel\"") >= 0) {
            start = indexOf(jsonString, "\"cFosChannel\": \"") + 16;
            end = indexOf(jsonString, "\"", start);
            params[0] = substring(jsonString, start, end);
        }
        
        if (indexOf(jsonString, "\"useDAPI\"") >= 0) {
            start = indexOf(jsonString, "\"useDAPI\": ") + 11;
            end = indexOf(jsonString, ",", start);
            if (end < 0) end = indexOf(jsonString, "\n", start);
            value = substring(jsonString, start, end);
            if (value == "true" || value == "1") {
                params[1] = 1;
            } else {
                params[1] = 0;
            }
        }
        
        if (indexOf(jsonString, "\"dapiChannel\"") >= 0) {
            start = indexOf(jsonString, "\"dapiChannel\": \"") + 16;
            end = indexOf(jsonString, "\"", start);
            params[2] = substring(jsonString, start, end);
        }
        
        if (indexOf(jsonString, "\"imageSource\"") >= 0) {
            start = indexOf(jsonString, "\"imageSource\": \"") + 16;
            end = indexOf(jsonString, "\"", start);
            params[3] = substring(jsonString, start, end);
        }
        
        if (indexOf(jsonString, "\"multiROI\"") >= 0) {
            start = indexOf(jsonString, "\"multiROI\": ") + 12;
            end = indexOf(jsonString, ",", start);
            value = substring(jsonString, start, end);
            if (value == "true" || value == "1") {
                params[4] = 1;
            } else {
                params[4] = 0;
            }
        }
        
        if (indexOf(jsonString, "\"roiCount\"") >= 0) {
            start = indexOf(jsonString, "\"roiCount\": ") + 12;
            end = indexOf(jsonString, ",", start);
            params[5] = parseInt(substring(jsonString, start, end));
        }
        
        if (indexOf(jsonString, "\"doImportROI\"") >= 0) {
            start = indexOf(jsonString, "\"doImportROI\": ") + 15;
            end = indexOf(jsonString, ",", start);
            value = substring(jsonString, start, end);
            if (value == "true" || value == "1") {
                params[6] = 1;
            } else {
                params[6] = 0;
            }
        }
        
        if (indexOf(jsonString, "\"exportROI\"") >= 0) {
            start = indexOf(jsonString, "\"exportROI\": ") + 13;
            end = indexOf(jsonString, ",", start);
            value = substring(jsonString, start, end);
            if (value == "true" || value == "1") {
                params[7] = 1;
            } else {
                params[7] = 0;
            }
        }
        
        if (indexOf(jsonString, "\"bgRadius\"") >= 0) {
            start = indexOf(jsonString, "\"bgRadius\": ") + 12;
            end = indexOf(jsonString, ",", start);
            params[8] = parseFloat(substring(jsonString, start, end));
        }
        
        if (indexOf(jsonString, "\"claheBlockSize\"") >= 0) {
            start = indexOf(jsonString, "\"claheBlockSize\": ") + 18;
            end = indexOf(jsonString, ",", start);
            params[9] = parseFloat(substring(jsonString, start, end));
        }
        
        if (indexOf(jsonString, "\"claheHistBins\"") >= 0) {
            start = indexOf(jsonString, "\"claheHistBins\": ") + 17;
            end = indexOf(jsonString, ",", start);
            params[10] = parseFloat(substring(jsonString, start, end));
        }
        
        if (indexOf(jsonString, "\"claheMaxSlope\"") >= 0) {
            start = indexOf(jsonString, "\"claheMaxSlope\": ") + 17;
            end = indexOf(jsonString, ",", start);
            params[11] = parseFloat(substring(jsonString, start, end));
        }
        
        if (indexOf(jsonString, "\"minNucleusSize\"") >= 0) {
            start = indexOf(jsonString, "\"minNucleusSize\": ") + 18;
            end = indexOf(jsonString, ",", start);
            params[12] = parseFloat(substring(jsonString, start, end));
        }
        
        if (indexOf(jsonString, "\"maxNucleusSize\"") >= 0) {
            start = indexOf(jsonString, "\"maxNucleusSize\": ") + 18;
            end = indexOf(jsonString, ",", start);
            params[13] = parseFloat(substring(jsonString, start, end));
        }
        
        if (indexOf(jsonString, "\"nucleusCircularity\"") >= 0) {
            start = indexOf(jsonString, "\"nucleusCircularity\": ") + 22;
            end = indexOf(jsonString, ",", start);
            params[14] = parseFloat(substring(jsonString, start, end));
        }
        
        if (indexOf(jsonString, "\"thresholdChoice\"") >= 0) {
            start = indexOf(jsonString, "\"thresholdChoice\": \"") + 20;
            end = indexOf(jsonString, "\"", start);
            params[15] = substring(jsonString, start, end);
        }
        
        if (indexOf(jsonString, "\"fullyAutomatic\"") >= 0) {
            start = indexOf(jsonString, "\"fullyAutomatic\": ") + 18;
            end = indexOf(jsonString, ",", start);
            value = substring(jsonString, start, end);
            if (value == "true" || value == "1") {
                params[16] = 1;
            } else {
                params[16] = 0;
            }
        }
        
        if (indexOf(jsonString, "\"minOverlap\"") >= 0) {
            start = indexOf(jsonString, "\"minOverlap\": ") + 14;
            end = indexOf(jsonString, ",", start);
            params[17] = parseFloat(substring(jsonString, start, end));
        }
        
        if (indexOf(jsonString, "\"minCfosSize\"") >= 0) {
            start = indexOf(jsonString, "\"minCfosSize\": ") + 15;
            end = indexOf(jsonString, ",", start);
            params[18] = parseFloat(substring(jsonString, start, end));
        }
        
        if (indexOf(jsonString, "\"maxCfosSize\"") >= 0) {
            start = indexOf(jsonString, "\"maxCfosSize\": ") + 15;
            end = indexOf(jsonString, ",", start);
            params[19] = parseFloat(substring(jsonString, start, end));
        }
        
        if (indexOf(jsonString, "\"cFosCircularity\"") >= 0) {
            start = indexOf(jsonString, "\"cFosCircularity\": ") + 19;
            end = indexOf(jsonString, ",", start);
            params[20] = parseFloat(substring(jsonString, start, end));
        }
        
        if (indexOf(jsonString, "\"dapiColor\"") >= 0) {
            start = indexOf(jsonString, "\"dapiColor\": \"") + 14;
            end = indexOf(jsonString, "\"", start);
            params[21] = substring(jsonString, start, end);
        }
        
        if (indexOf(jsonString, "\"useGreenChannel\"") >= 0) {
            start = indexOf(jsonString, "\"useGreenChannel\": ") + 19;
            end = indexOf(jsonString, ",", start);
            value = substring(jsonString, start, end);
            if (value == "true" || value == "1") {
                params[22] = 1;
            } else {
                params[22] = 0;
            }
        }
        
        if (indexOf(jsonString, "\"saveOverlay\"") >= 0) {
            start = indexOf(jsonString, "\"saveOverlay\": ") + 15;
            end = indexOf(jsonString, ",", start);
            value = substring(jsonString, start, end);
            if (value == "true" || value == "1") {
                params[23] = 1;
            } else {
                params[23] = 0;
            }
        }
        
        if (indexOf(jsonString, "\"saveROIPosition\"") >= 0) {
            start = indexOf(jsonString, "\"saveROIPosition\": ") + 19;
            end = indexOf(jsonString, "\n", start);
            if (end < 0) end = indexOf(jsonString, "}", start);
            value = substring(jsonString, start, end);
            if (value == "true" || value == "1") {
                params[24] = 1;
            } else {
                params[24] = 0;
            }
        }
    }
    
    return params;
}

// Initialize default settings (these will persist across analysis runs)
defaultCFosChannel = "Red";
defaultUseDAPI = true;
defaultDAPIChannel = "Blue";
defaultChoice = "Directory";
defaultMultiROI = false;
defaultROICount = 2;
defaultDoImportROI = false;
defaultExportROI = false;
defaultBgRadius = 100;
defaultClaheBlockSize = 16;
defaultClaheHistBins = 256;
defaultClaheMaxSlope = 2.0;
defaultMinNucleusSize = 50;
defaultMaxNucleusSize = 500;
defaultNucleusCircularity = 0.5;
defaultThresholdChoice = "Manual";
defaultFullyAutomatic = false;
defaultMinOverlap = 40;
defaultMinCfosSize = 30;
defaultMaxCfosSize = 250;
defaultCFosCircularity = 0.4;
defaultDapiColor = "green";
defaultUseGreenChannel = true;
defaultSaveOverlay = true;
defaultSaveROIPosition = true;

// Variable to track last used directory for config loading
lastUsedDir = "";

// Main loop - continues until user chooses to exit
continueAnalysis = true;

while (continueAnalysis) {
    // Load configuration from last used directory if available
    if (lastUsedDir != "" && File.exists(lastUsedDir + "cfos_config.json")) {
        configParams = loadConfiguration(lastUsedDir + "cfos_config.json");
        defaultCFosChannel = configParams[0];
        defaultUseDAPI = configParams[1];
        defaultDAPIChannel = configParams[2];
        defaultChoice = configParams[3];
        defaultMultiROI = configParams[4];
        defaultROICount = configParams[5];
        defaultDoImportROI = configParams[6];
        defaultExportROI = configParams[7];
        defaultBgRadius = configParams[8];
        defaultClaheBlockSize = configParams[9];
        defaultClaheHistBins = configParams[10];
        defaultClaheMaxSlope = configParams[11];
        defaultMinNucleusSize = configParams[12];
        defaultMaxNucleusSize = configParams[13];
        defaultNucleusCircularity = configParams[14];
        defaultThresholdChoice = configParams[15];
        defaultFullyAutomatic = configParams[16];
        defaultMinOverlap = configParams[17];
        defaultMinCfosSize = configParams[18];
        defaultMaxCfosSize = configParams[19];
        defaultCFosCircularity = configParams[20];
        defaultDapiColor = configParams[21];
        defaultUseGreenChannel = configParams[22];
        defaultSaveOverlay = configParams[23];
        defaultSaveROIPosition = configParams[24];
    }
    // Ask user to choose directory with images or a single file
    Dialog.create("c-Fos Cell Counter");
    Dialog.addMessage("c-Fos Counting Macro for Fluorescence Images", 16, "#E52020");
    Dialog.addMessage("Configure channel settings and analysis parameters", 12, "#3D3B40");
    Dialog.addMessage("-----------------------");

    // NEW: Channel Configuration Section
    Dialog.addMessage("CHANNEL CONFIGURATION", 14, "#A0153E");
    Dialog.addChoice("c-Fos channel:", newArray("Red", "Green", "Blue"), defaultCFosChannel);
    Dialog.addCheckbox("Use DAPI for colocalization check", defaultUseDAPI);
    Dialog.addChoice("DAPI channel:", newArray("Blue", "Green", "Red"), defaultDAPIChannel);

// Tab 1: Analysis Mode and ROI Settings
Dialog.addMessage("BATCH SETTINGS", 14, "#A0153E");
Dialog.addChoice("Image Source:", newArray("Directory", "Single Image"));

// Create panel for ROI settings
Dialog.addMessage("ROI SETTINGS", 14, "#A0153E");
importedROICount = 0;
Dialog.addCheckbox("Enable multiple ROI analysis", false);
Dialog.addNumber("Number of ROIs:", 2, 0, 3, "");
Dialog.addCheckbox("Import ROI settings", false);
Dialog.addCheckbox("Export ROI settings after defining ROIs", false);

// Tab 2: Image Processing Parameters
Dialog.addMessage("IMAGE PREPROCESSING", 14, "#A0153E");
Dialog.addNumber("Background subtraction radius:", 100);

// Fix the CLAHE parameters layout - don't use addToSameRow() after the header
Dialog.addMessage("CLAHE Parameters:", 12, "#00224D");
Dialog.addNumber("Block size:", 16);
Dialog.addToSameRow();  // Only add toSameRow between actual parameters
Dialog.addNumber("Histogram bins:", 256);
Dialog.addToSameRow();
Dialog.addNumber("Max slope:", 2.0);

// Tab 3: Detection Parameters
Dialog.addMessage("DETECTION PARAMETERS", 14, "#A0153E");
Dialog.addMessage("DAPI Detection (if enabled):", 12, "#00224D");
Dialog.addNumber("Min nucleus size (px):", 50);
Dialog.addToSameRow();
Dialog.addNumber("Max nucleus size (px):", 500);
Dialog.addToSameRow();
Dialog.addSlider("DAPI Circularity (0-1):", 0.3, 1, 0.5);

Dialog.addMessage("c-Fos Detection:", 12, "#00224D");
Dialog.addChoice("Threshold method:", newArray("Manual", "Automatic (Yen)", "Automatic (RenyiEntropy)"), "Manual");
Dialog.addToSameRow();
Dialog.addCheckbox("Skip manual adjustment", false);
Dialog.addNumber("Min overlap with DAPI (%):", 40);
Dialog.addToSameRow();
Dialog.addNumber("Min c-Fos size (px):", 30);
Dialog.addToSameRow();
Dialog.addNumber("Max c-Fos size (px):", 250);
Dialog.addSlider("c-Fos Circularity (0-1):", 0.3, 1, 0.4);

// Tab 4: Visualization and Output Options
Dialog.addMessage("VISUALIZATION & OUTPUT", 14, "#A0153E");
Dialog.addString("DAPI outline color:", "green");
Dialog.addToSameRow();
Dialog.addCheckbox("Use green channel for outlines", true);
Dialog.addCheckbox("Save overlay images", true);
Dialog.addToSameRow();
Dialog.addCheckbox("Save ROI position reference", true);

Dialog.show();

// NEW: Get channel configuration
cFosChannelChoice = Dialog.getChoice();
cFosChannel = toLowerCase(cFosChannelChoice);
useDAPI = Dialog.getCheckbox();
dapiChannelChoice = Dialog.getChoice();
dapiChannel = toLowerCase(dapiChannelChoice);

// Get user choices
choice = Dialog.getChoice();
multiROI = Dialog.getCheckbox();
roiCountFromDialog = Dialog.getNumber();
doImportROISettings = Dialog.getCheckbox();
exportROISettingsAfter = Dialog.getCheckbox();
bgRadius = Dialog.getNumber();
claheBlockSize = Dialog.getNumber();
claheHistBins = Dialog.getNumber();
claheMaxSlope = Dialog.getNumber();
minNucleusSize = Dialog.getNumber();
maxNucleusSize = Dialog.getNumber();
nucleusCircularity = Dialog.getNumber();

claheBlockSizeDAPI = 50;
claheMaxSlopeDAPI = 1.5;

// Get threshold method
thresholdChoice = Dialog.getChoice();
if (thresholdChoice == "Manual") {
    manualThreshold = true;
    thresholdMethod = "Yen"; // Default if manual fails
} else if (thresholdChoice == "Automatic (Yen)") {
    manualThreshold = false;
    thresholdMethod = "Yen";
} else {
    manualThreshold = false;
    thresholdMethod = "RenyiEntropy";
}

fullyAutomatic = Dialog.getCheckbox();
minOverlap = Dialog.getNumber();
minCfosSize = Dialog.getNumber();
maxCfosSize = Dialog.getNumber();
cFosCircularity = Dialog.getNumber();
cFosMarkerStyle = "yellow cross";
dapiColor = Dialog.getString();
dapiWidth = 0.4;
cFosMarkerWidth = 0.8;
useGreenChannel = Dialog.getCheckbox();
saveOverlay = Dialog.getCheckbox();
saveROIPosition = Dialog.getCheckbox();

// Import ROI settings if requested
if (doImportROISettings) {
    importedCount = importROISettings();
    if (importedCount > 0) {
        roiCount = importedCount;
        hasImportedROISettings = true;
        multiROI = true;
    } else {
        roiCount = roiCountFromDialog;
        hasImportedROISettings = false;
    }
} else {
    roiCount = roiCountFromDialog;
    hasImportedROISettings = false;
}

// Set up batch processing if directory selected
if (choice == "Directory") {
    dir = getDirectory("Select Directory with TIF Images");
    fileList = getFileList(dir);
    
    // Filter to only include TIF files
    tifFiles = newArray(0);
    for (i=0; i<fileList.length; i++) {
        if (endsWith(fileList[i], ".tif") || endsWith(fileList[i], ".TIF")) {
            tifFiles = Array.concat(tifFiles, fileList[i]);
        }
    }
    
    // Check if there are any TIF files in the directory
    if (tifFiles.length == 0) {
        showMessage("No TIF Files", "No TIF files were found in the selected directory.\nPlease select a different directory.");
        exit();
    }
    
    // Create dialog for user to select which images to process
    Dialog.create("Select Images to Process");
    Dialog.addMessage("Select the TIF images you want to analyze:");
    
    // Add checkboxes for each TIF file (all checked by default)
    fileToProcess = newArray(tifFiles.length);
    for (i=0; i<tifFiles.length; i++) {
        Dialog.addCheckbox(tifFiles[i], true);
    }
    
    Dialog.addMessage("Click 'OK' to proceed with analysis of selected images.");
    Dialog.show();
    
    // Get user selections
    selectedFiles = newArray(0);
    for (i=0; i<tifFiles.length; i++) {
        fileToProcess[i] = Dialog.getCheckbox();
        if (fileToProcess[i]) {
            selectedFiles = Array.concat(selectedFiles, tifFiles[i]);
        }
    }
    
    // Check if user selected any files
    if (selectedFiles.length == 0) {
        showMessage("No Files Selected", "No files were selected for analysis.\nExiting macro.");
        exit();
    }
    
    // Create output directory
    outputDir = dir + "Results" + File.separator;
    File.makeDirectory(outputDir);
    
    // Create a log file
    logFile = File.open(outputDir + "analysis_log.txt");
    print(logFile, "c-Fos Cell Counting Analysis");
    print(logFile, "Analysis performed on: " + getDateTime());
    print(logFile, "\nParameters used:");
    print(logFile, "c-Fos channel: " + cFosChannel);
    
    if (useDAPI) {
        print(logFile, "DAPI channel: " + dapiChannel);
        print(logFile, "DAPI colocalization check: Enabled");
    } else {
        print(logFile, "DAPI colocalization check: Disabled");
    }
    
    print(logFile, "Background subtraction radius: " + bgRadius);
    print(logFile, "CLAHE enhancement: block size=" + claheBlockSize + 
          ", histogram bins=" + claheHistBins + ", max slope=" + claheMaxSlope);
    
    if (useDAPI) {
        print(logFile, "Min nucleus size: " + minNucleusSize + " pixels");
        print(logFile, "Max nucleus size: " + maxNucleusSize + " pixels");
        print(logFile, "DAPI nucleus circularity: " + nucleusCircularity);
        print(logFile, "Min overlap with DAPI: " + minOverlap + "%");
    }
    
    print(logFile, "c-Fos size range: " + minCfosSize + "-" + maxCfosSize + " pixels");
    print(logFile, "c-Fos circularity: " + cFosCircularity);
    
    // Build threshold method text
    thresholdingText = "";
    if (manualThreshold) {
        thresholdingText = "Manual";
    } else {
        thresholdingText = "Automatic (" + thresholdMethod + ")";
    }
    
    if (fullyAutomatic) {
        thresholdingText = thresholdingText + " (Fully automatic mode)";
    }
    
    print(logFile, "c-Fos thresholding: " + thresholdingText);
    
    // Build ROI mode text
    roiModeText = "";
    if (multiROI) {
        roiModeText = "Enabled";
    } else {
        roiModeText = "Disabled";
    }
    
    print(logFile, "Multiple ROI mode: " + roiModeText);
    print(logFile, "\nRESULTS SUMMARY:");
    print(logFile, "Filename\tROI Name\tc-Fos+ Cells\tROI Area (px²)");
    File.close(logFile);
    
    // Create debug log window
    print("\\Clear");
    print("===== BATCH PROCESSING DEBUG LOG =====");
    print("Starting batch processing of " + selectedFiles.length + " files");
    print("c-Fos channel: " + cFosChannel);
    if (useDAPI) {
        print("DAPI channel: " + dapiChannel + " (colocalization check enabled)");
    } else {
        print("DAPI analysis: Disabled");
    }
    
    setBatchMode(false);
    
    // Process each file
    validCount = 0;
    resultRowIndex = 0;
    
    // Reset global arrays
    allNumbers = newArray(0);
    allRois = newArray(0);
    allFileNames = newArray(0);
    allTotalDapi = newArray(0);
    allCFosCells = newArray(0);
    allROIAreas = newArray(0);
    allCFosDensity = newArray(0);
    
    globalBrainRegions = newArray(0);
    
    // Create a table for summary results
    Table.create("Batch Summary");
    
    // Process each selected file
    for (i=0; i<selectedFiles.length; i++) {
        fullPath = dir + selectedFiles[i];
        print("Attempting to process file: " + fullPath);
        
        if (File.exists(fullPath)) {
            print("  File exists. Processing...");
            setBatchMode(false);
            resultRowIndex = processImage(fullPath, outputDir, resultRowIndex, i, selectedFiles[i]);
            setBatchMode(true);
            validCount++;
        } else {
            print("  ERROR: File does not exist: " + fullPath);
        }
    }
    
    // Create comprehensive batch summary
    if (validCount > 0) {
        print("\nPreparing comprehensive summary...");
        print("Total data points collected: " + allNumbers.length);
        
        // Determine unique brain regions for columns
        uniqueRegions = newArray(0);
        for (i=0; i<allRois.length; i++) {
            regionExists = false;
            for (j=0; j<uniqueRegions.length; j++) {
                if (allRois[i] == uniqueRegions[j]) {
                    regionExists = true;
                    break;
                }
            }
            if (!regionExists) {
                uniqueRegions = Array.concat(uniqueRegions, allRois[i]);
            }
        }
        
        print("Unique regions found: " + uniqueRegions.length);
        
        // Extract sample ID and brain region from first file
        fileInfo = extractFileInfo(selectedFiles[0]);
        sampleID = fileInfo[0];
        brainRegion = fileInfo[1];
        summaryFilename = sampleID + "_" + brainRegion + "_cfos_summary.csv";
        
        // Create comprehensive summary table
        Table.create("Comprehensive Summary");
        
        Table.setColumn("Number", newArray(""));
        for (i=0; i<uniqueRegions.length; i++) {
            Table.setColumn(uniqueRegions[i], newArray(0));
        }
        Table.deleteRows(0, 0);
        
        // Get unique image numbers
        uniqueNumbers = newArray(0);
        for (i=0; i<allNumbers.length; i++) {
            numExists = false;
            for (j=0; j<uniqueNumbers.length; j++) {
                if (allNumbers[i] == uniqueNumbers[j]) {
                    numExists = true;
                    break;
                }
            }
            if (!numExists) {
                uniqueNumbers = Array.concat(uniqueNumbers, allNumbers[i]);
            }
        }
        
        // Sort if numeric
        allNumeric = true;
        for (i=0; i<uniqueNumbers.length; i++) {
            if (!matches(uniqueNumbers[i], "^[0-9]+$")) {
                allNumeric = false;
                break;
            }
        }
        
        if (allNumeric) {
            numArray = newArray(uniqueNumbers.length);
            for (i=0; i<uniqueNumbers.length; i++) {
                numArray[i] = parseInt(uniqueNumbers[i]);
            }
            
            // Bubble sort
            for (i=0; i<numArray.length-1; i++) {
                for (j=0; j<numArray.length-i-1; j++) {
                    if (numArray[j] > numArray[j+1]) {
                        temp = numArray[j];
                        numArray[j] = numArray[j+1];
                        numArray[j+1] = temp;
                        
                        temp = uniqueNumbers[j];
                        uniqueNumbers[j] = uniqueNumbers[j+1];
                        uniqueNumbers[j+1] = temp;
                    }
                }
            }
        }
        
        // Add rows for each unique number
        for (i=0; i<uniqueNumbers.length; i++) {
            rowIndex = Table.size;
            Table.set("Number", rowIndex, uniqueNumbers[i]);
            
            for (j=0; j<uniqueRegions.length; j++) {
                region = uniqueRegions[j];
                for (k=0; k<allNumbers.length; k++) {
                    if (allNumbers[k] == uniqueNumbers[i] && allRois[k] == region) {
                        Table.set(region, rowIndex, allCFosCells[k]);
                        break;
                    }
                }
            }
        }
        
        // Add blank row separator
        rowIndex = Table.size;
        Table.set("Number", rowIndex, "");
        
        // Add Total row
        rowIndex = Table.size;
        Table.set("Number", rowIndex, "Total");
        
        for (j=0; j<uniqueRegions.length; j++) {
            region = uniqueRegions[j];
            regionTotal = 0;
            
            for (k=0; k<Table.size-2; k++) {
                value = Table.get(region, k);
                if (value != "" && !isNaN(parseFloat(value))) {
                    regionTotal += parseFloat(value);
                }
            }
            
            Table.set(region, rowIndex, regionTotal);
        }
        
        // Add Mean row
        rowIndex = Table.size;
        Table.set("Number", rowIndex, "Mean");
        
        for (j=0; j<uniqueRegions.length; j++) {
            region = uniqueRegions[j];
            regionTotal = 0;
            validCount = 0;
            
            for (k=0; k<Table.size-3; k++) {
                value = Table.get(region, k);
                if (value != "" && !isNaN(parseFloat(value))) {
                    regionTotal += parseFloat(value);
                    validCount++;
                }
            }
            
            regionMean = 0;
            if (validCount > 0) {
                regionMean = regionTotal / validCount;
            }
            
            regionMean = Math.round(regionMean * 100) / 100;
            Table.set(region, rowIndex, regionMean);
        }
        
        // Save summaries
        Table.save(outputDir + summaryFilename);
        
        selectWindow("Batch Summary");
        Table.save(outputDir + "batch_summary.csv");
    }
    
    setBatchMode(false);
    
    // Ask user if they want to continue with another analysis
    Dialog.create("Batch Processing Complete");
    Dialog.addMessage("Processed " + validCount + " images.", 14, "#191970");
    Dialog.addMessage("Results saved to: " + outputDir, 12, "gray");
    Dialog.addCheckbox("Start another analysis", true);
    Dialog.show();
    
    continueAnalysis = Dialog.getCheckbox();
    
} else {
    // Process single image
    input = File.openDialog("Select a TIF image file");
    outputDir = File.getDirectory(input);
    lastUsedDir = outputDir;  // Save for next iteration
    
    // Save configuration to the selected directory
    configParams = newArray(25);
    configParams[0] = cFosChannelChoice;
    if (useDAPI) {
        configParams[1] = 1;
    } else {
        configParams[1] = 0;
    }
    configParams[2] = dapiChannelChoice;
    configParams[3] = choice;
    if (multiROI) {
        configParams[4] = 1;
    } else {
        configParams[4] = 0;
    }
    configParams[5] = roiCountFromDialog;
    if (doImportROISettings) {
        configParams[6] = 1;
    } else {
        configParams[6] = 0;
    }
    if (exportROISettingsAfter) {
        configParams[7] = 1;
    } else {
        configParams[7] = 0;
    }
    configParams[8] = bgRadius;
    configParams[9] = claheBlockSize;
    configParams[10] = claheHistBins;
    configParams[11] = claheMaxSlope;
    configParams[12] = minNucleusSize;
    configParams[13] = maxNucleusSize;
    configParams[14] = nucleusCircularity;
    configParams[15] = thresholdChoice;
    if (fullyAutomatic) {
        configParams[16] = 1;
    } else {
        configParams[16] = 0;
    }
    configParams[17] = minOverlap;
    configParams[18] = minCfosSize;
    configParams[19] = maxCfosSize;
    configParams[20] = cFosCircularity;
    configParams[21] = dapiColor;
    if (useGreenChannel) {
        configParams[22] = 1;
    } else {
        configParams[22] = 0;
    }
    if (saveOverlay) {
        configParams[23] = 1;
    } else {
        configParams[23] = 0;
    }
    if (saveROIPosition) {
        configParams[24] = 1;
    } else {
        configParams[24] = 0;
    }
    
    saveConfiguration(outputDir + "cfos_config.json", configParams);
    
    processImage(input, outputDir, 0, 0, File.getName(input));
    
    // Ask user if they want to continue with another analysis
    Dialog.create("Analysis Complete");
    Dialog.addMessage("Results saved to: " + outputDir, 12, "gray");
    Dialog.addCheckbox("Start another analysis", true);
    Dialog.show();
    
    continueAnalysis = Dialog.getCheckbox();
}

} // End of main loop

function processImage(imagePath, outputDir, tableRowStart, fileIndex, originalFilename) {
    currentTableRow = tableRowStart;
    
    if (choice == "Directory") {
        print("  Opening image: " + imagePath);
    }
    
    if (!File.exists(imagePath)) {
        print("  ERROR: File not found: " + imagePath);
        return currentTableRow;
    }
    
    open(imagePath);
    
    if (nImages == 0) {
        print("  ERROR: Failed to open image.");
        return currentTableRow;
    }
    
    originalTitle = getTitle();
    
    if (choice == "Directory") {
        print("  Successfully opened image: " + originalTitle);
    }
    
    getDimensions(originalWidth, originalHeight, channels, slices, frames);
    
    // Extract filename
    filename = File.getName(imagePath);
    dotIndex = lastIndexOf(filename, ".");
    if (dotIndex != -1) {
        filename = substring(filename, 0, dotIndex);
    }
    
    sequenceNumber = extractSequenceNumber(filename);
    
    if (sequenceNumber == "") {
        sequenceNumber = filename;
    }
    
    // Initialize ROI Manager
    roiManager("reset");
    
    // Define ROIs
    if (multiROI) {
        defineMultipleROIs(originalTitle);
    } else {
        defineSingleROI(originalTitle);
    }
    
    roiCount = roiManager("count");
    if (roiCount == 0) {
        showMessage("No ROIs defined", "At least one ROI must be defined for analysis.");
        return currentTableRow;
    }
    
    // Save ROI position if enabled
    if (saveROIPosition) {
        saveROIPositionImage(originalTitle, filename, outputDir);
    }
    
    // Get bounding box for all ROIs
    minX = originalWidth;
    minY = originalHeight;
    maxX = 0;
    maxY = 0;
    
    for (roi = 0; roi < roiCount; roi++) {
        roiManager("select", roi);
        Roi.getBounds(x, y, w, h);
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x + w > maxX) maxX = x + w;
        if (y + h > maxY) maxY = y + h;
    }
    
    // Crop with margin
    margin = 20;
    cropX = maxOf(0, minX - margin);
    cropY = maxOf(0, minY - margin);
    cropWidth = minOf(originalWidth - cropX, maxX - minX + 2*margin);
    cropHeight = minOf(originalHeight - cropY, maxY - minY + 2*margin);
    
    selectWindow(originalTitle);
    makeRectangle(cropX, cropY, cropWidth, cropHeight);
    run("Duplicate...", "title=Cropped duplicate");
    
    // Create ROI masks
    roiMasks = newArray(roiCount);
    roiAreas = newArray(roiCount);
    roiNames = newArray(roiCount);
    
    for (roi = 0; roi < roiCount; roi++) {
        roiManager("select", roi);
        roiNames[roi] = Roi.getName();
        
        List.setMeasurements;
        roiAreas[roi] = List.getValue("Area");
        
        newImage("ROI_Mask_" + roi, "8-bit black", originalWidth, originalHeight, 1);
        roiManager("select", roi);
        setForegroundColor(255, 255, 255);
        run("Fill", "slice");
        
        makeRectangle(cropX, cropY, cropWidth, cropHeight);
        run("Duplicate...", "title=Cropped_ROI_Mask_" + roi);
        selectWindow("ROI_Mask_" + roi);
        close();
        
        roiMasks[roi] = "Cropped_ROI_Mask_" + roi;
    }
    
    // Use cropped image
    selectWindow("Cropped");
    
    // Split channels
    run("Split Channels");
    
    // NEW: Flexible channel assignment
    allWindows = getList("image.titles");
    
    cFosWindowName = "";
    dapiWindowName = "";
    
    // Find channels based on user configuration
    for (i=0; i<allWindows.length; i++) {
        windowName = allWindows[i];
        
        // Match c-Fos channel
        if (cFosChannel == "red" && (indexOf(windowName, "red") >= 0 || indexOf(windowName, "C1-") >= 0)) {
            cFosWindowName = windowName;
        } else if (cFosChannel == "green" && (indexOf(windowName, "green") >= 0 || indexOf(windowName, "C2-") >= 0)) {
            cFosWindowName = windowName;
        } else if (cFosChannel == "blue" && (indexOf(windowName, "blue") >= 0 || indexOf(windowName, "C3-") >= 0)) {
            cFosWindowName = windowName;
        }
        
        // Match DAPI channel (only if DAPI is enabled)
        if (useDAPI) {
            if (dapiChannel == "blue" && (indexOf(windowName, "blue") >= 0 || indexOf(windowName, "C3-") >= 0)) {
                dapiWindowName = windowName;
            } else if (dapiChannel == "green" && (indexOf(windowName, "green") >= 0 || indexOf(windowName, "C2-") >= 0)) {
                dapiWindowName = windowName;
            } else if (dapiChannel == "red" && (indexOf(windowName, "red") >= 0 || indexOf(windowName, "C1-") >= 0)) {
                dapiWindowName = windowName;
            }
        }
    }
    
    // Check if c-Fos channel was found
    if (cFosWindowName == "") {
        showMessage("Error", "Could not identify c-Fos channel (" + cFosChannel + ").\n" +
                  "Available windows: " + String.join(allWindows, ", "));
        return currentTableRow;
    }
    
    // Rename c-Fos channel
    selectWindow(cFosWindowName);
    rename("cFos");
    
    // Process DAPI if enabled
    if (useDAPI) {
        if (dapiWindowName == "") {
            showMessage("Error", "Could not identify DAPI channel (" + dapiChannel + ").\n" +
                      "Available windows: " + String.join(allWindows, ", "));
            return currentTableRow;
        }
        
        selectWindow(dapiWindowName);
        rename("DAPI");
        
        // Process DAPI
        selectWindow("DAPI");
        run("Subtract Background...", "rolling=" + bgRadius);
        run("CLAHE ", "blocksize=" + claheBlockSizeDAPI + " histogram=" + claheHistBins + " maximum=" + claheMaxSlopeDAPI);
        
        run("Duplicate...", "title=DAPI_mask");
        
        setAutoThreshold("Otsu dark");
        setOption("BlackBackground", true);
        run("Convert to Mask");
        run("Fill Holes");
        run("Watershed");
    }
    
    // Process c-Fos channel
    selectWindow("cFos");
    run("Subtract Background...", "rolling=" + bgRadius);
    run("CLAHE ", "blocksize=" + claheBlockSize + " histogram=" + claheHistBins + " maximum=" + claheMaxSlope);
    run("Duplicate...", "title=cFos_processed");
    selectWindow("cFos");
    run("Median...", "radius=2");
    run("Duplicate...", "title=cFos_mask");
    
    // Threshold c-Fos
    if (manualThreshold && !fullyAutomatic) {
        // Create a reference image for better visualization during threshold adjustment
        selectWindow("cFos_processed");
        run("Duplicate...", "title=cFos_reference");
        resetMinAndMax();
        run("Enhance Contrast", "saturated=0.35");
        
        // Create merged reference image
        if (useDAPI) {
            // Create DAPI reference
            selectWindow("DAPI");
            run("Duplicate...", "title=DAPI_reference");
            resetMinAndMax();
            run("Enhance Contrast", "saturated=0.35");
            
            // Merge c-Fos and DAPI for reference
            run("Merge Channels...", "c1=cFos_reference c3=DAPI_reference create keep");
            rename("Reference_Merged");
            
            // Set display properties for better visualization
            Stack.setChannel(1);
            resetMinAndMax();
            Stack.setChannel(2);
            resetMinAndMax();
            Stack.setDisplayMode("composite");
        } else {
            // Without DAPI, convert c-Fos to RGB for consistency
            selectWindow("cFos_reference");
            run("RGB Color");
            rename("Reference_Merged");
        }
        
        // Position the reference window
        selectWindow("Reference_Merged");
        
        // Now set up threshold on the mask
        selectWindow("cFos_mask");
        resetMinAndMax();
        run("Enhance Contrast", "saturated=0.35");
        
        setAutoThreshold(thresholdMethod + " dark");
        run("Threshold...");
        
        // Display instruction message
        if (useDAPI) {
            waitForUser("c-Fos Threshold", 
                "Adjust the threshold to segment c-Fos positive cells.\n \n" +
                "Reference image shows:\n" +
                "  - Red: c-Fos (processed)\n" +
                "  - Blue: DAPI\n \n" +
                "Use 'Image > Color > Channels Tool' to switch channels in reference.\n" +
                "When satisfied with threshold, click 'OK'.");
        } else {
            waitForUser("c-Fos Threshold", 
                "Adjust the threshold to segment c-Fos positive cells.\n \n" +
                "Reference image shows c-Fos (processed).\n \n" +
                "When satisfied with threshold, click 'OK'.");
        }
        
        // Get the threshold values
        selectWindow("cFos_mask");
        getThreshold(lower, upper);
        
        // Close threshold dialog and reference image
        selectWindow("Threshold");
        run("Close");
        
        selectWindow("Reference_Merged");
        close();
        
        // Apply the threshold
        selectWindow("cFos_mask");
        setThreshold(lower, upper);
    } else {
        selectWindow("cFos_mask");
        setAutoThreshold(thresholdMethod + " dark");
    }
    
    setOption("BlackBackground", true);
    run("Convert to Mask");
    run("Fill Holes");
    run("Watershed");
    
    // Create results tables
    if (choice != "Directory") {
        if (isOpen("Detailed_Results")) {
            selectWindow("Detailed_Results");
            run("Close");
        }
        Table.create("Detailed_Results");
        Table.setColumn("ROI Name", newArray(""));
        
        if (useDAPI) {
            Table.setColumn("Total DAPI Nuclei", newArray(0));
        }
        
        Table.setColumn("c-Fos+ Cells", newArray(0));
        Table.setColumn("ROI Area (px²)", newArray(0));
        Table.setColumn("Density (cells/px²)", newArray(0));
        Table.deleteRows(0, 0);
    }
    
    // Create summary table
    if (isOpen("Summary_Results")) {
        selectWindow("Summary_Results");
        run("Close");
    }
    Table.create("Summary_Results");
    
    // Build metrics list based on DAPI usage
    if (useDAPI) {
        metrics = newArray(
            "Total DAPI",
            "Total c-Fos Objects",
            "c-Fos+ Cells",
            "ROI Area (px²)",
            "c-Fos+ Density",
            "Min DAPI Overlap (%)"
        );
    } else {
        metrics = newArray(
            "Total c-Fos Objects",
            "c-Fos+ Cells",
            "ROI Area (px²)",
            "c-Fos+ Density"
        );
    }
    
    Table.setColumn("Metric", metrics);
    Table.update;
    
    // Process each ROI
    for (roi = 0; roi < roiCount; roi++) {
        roiName = roiNames[roi];
        roiArea = roiAreas[roi];
        roiMask = roiMasks[roi];
        
        processROI(roi, roiName, roiArea, roiMask, filename, outputDir, sequenceNumber);
        
        currentTableRow++;
    }
    
    // Save results
    Table.save(outputDir + filename + "_result.csv");
    
    // Close windows
    run("Close All");
    if (isOpen("ROI Manager")) {
        selectWindow("ROI Manager");
        run("Close");
    }
    
    return currentTableRow;
}

function defineSingleROI(imageTitle) {
    selectWindow(imageTitle);
    
    selectionValid = false;
    while (!selectionValid) {
        setTool("polygon");
        waitForUser("Define Brain Region", "Use the polygon tool to outline the brain region.\nClick 'OK' when done.");
        
        if (selectionType() == -1) {
            Dialog.create("No Selection Made");
            Dialog.addMessage("No ROI was selected. Would you like to:");
            Dialog.addChoice("Option:", newArray("Try selecting an ROI again", "Use the entire image"));
            Dialog.show();
            
            userChoice = Dialog.getChoice();
            if (userChoice == "Use the entire image") {
                showMessage("Using entire image", "Proceeding with the entire image as the ROI.");
                run("Select All");
                selectionValid = true;
            }
        } else {
            selectionValid = true;
        }
    }
    
    roiManager("Add");
    roiManager("Select", 0);
    roiManager("Rename", "Region1");
}

function defineMultipleROIs(imageTitle) {
    selectWindow(imageTitle);
    roiManager("reset");
    
    if (!hasImportedROISettings) {
        roiNames = newArray(roiCount);
        for (i = 0; i < roiCount; i++) {
            roiNames[i] = "Region" + (i+1);
        }
    }
    
    run("Duplicate...", "title=ROI_Selection_Image");
    
    run("Select None");
    Overlay.remove;
    
    roiColors = newArray("#E9DF00", "#01FDF6", "#16C47F", "#FEFCFD", "#FB9F89", "#CBBAED", "#CAE9FF", "#8000FF", "#00FF80", "#FF0080");
    
    allROIs = newArray(roiCount);
    
    for (i = 0; i < roiCount; i++) {
        selectionValid = false;
        while (!selectionValid) {
            selectWindow("ROI_Selection_Image");
            setTool("polygon");
            
            message = "Use the polygon tool to outline region " + (i+1);
            if (hasImportedROISettings && i < roiNames.length) {
                message = message + " (" + roiNames[i] + ")";
            }
            message = message + "\nClick 'OK' when done.\n";
            message = message + "Previously defined ROIs are shown in the overlay.";
            
            waitForUser("Define ROI #" + (i+1), message);
            
            if (selectionType() == -1) {
                Dialog.create("No Selection Made");
                Dialog.addMessage("No ROI was selected for Region #" + (i+1) + ". Would you like to:");
                Dialog.addChoice("Option:", newArray("Try selecting this ROI again", "Skip this ROI", "Use the entire image for this ROI"));
                Dialog.show();
                
                userChoice = Dialog.getChoice();
                if (userChoice == "Skip this ROI") {
                    selectionValid = true;
                    continue;
                } else if (userChoice == "Use the entire image for this ROI") {
                    run("Select All");
                    selectionValid = true;
                }
            } else {
                selectionValid = true;
            }
        }
        
        if (selectionType() == -1) {
            continue;
        }
        
        roiName = "";
        if (hasImportedROISettings && i < roiNames.length) {
            roiName = roiNames[i];
        } else {
            Dialog.create("ROI Name");
            Dialog.addString("Name for ROI #" + (i+1) + ":", "Region" + (i+1));
            Dialog.show();
            roiName = Dialog.getString();
            roiNames[i] = roiName;
        }
        
        currentROI = i;
        
        colorIndex = i % roiColors.length;
        color = roiColors[colorIndex];
        
        r = parseInt(substring(color, 1, 3), 16);
        g = parseInt(substring(color, 3, 5), 16);
        b = parseInt(substring(color, 5, 7), 16);
        
        run("Properties... ", "stroke=#" + substring(color, 1) + " width=2");
        Overlay.addSelection;
        
        Roi.getCoordinates(xpoints, ypoints);
        xSum = 0;
        ySum = 0;
        for (p = 0; p < xpoints.length; p++) {
            xSum += xpoints[p];
            ySum += ypoints[p];
        }
        xCenter = xSum / xpoints.length;
        yCenter = ySum / ypoints.length;
        
        setFont("SansSerif", 14, "bold antialiased");
        setColor(r, g, b);
        Overlay.drawString(roiName, xCenter, yCenter);
        Overlay.show;
        
        roiPath = getDirectory("temp") + "temp_roi_" + i + ".roi";
        roiManager("reset");
        run("Select None");
        run("Restore Selection");
        roiManager("Add");
        roiManager("Select", 0);
        roiManager("Save", roiPath);
        allROIs[i] = roiPath;
        
        run("Select None");
    }
    
    selectWindow("ROI_Selection_Image");
    close();
    
    selectWindow(imageTitle);
    
    roiManager("reset");
    for (i = 0; i < roiCount; i++) {
        if (allROIs[i] != 0) {
            roiManager("Open", allROIs[i]);
            roiManager("Select", roiManager("count")-1);
            roiManager("Rename", roiNames[i]);
            
            File.delete(allROIs[i]);
        }
    }
    
    if (exportROISettingsAfter && !hasImportedROISettings) {
        exportROISettings(roiCount, roiNames);
    }
}

function saveROIPositionImage(imageTitle, filename, outputDir) {
    selectWindow(imageTitle);
    
    getDimensions(width, height, channels, slices, frames);
    newImage("ROI_Reference", "RGB", width, height, 1);
    
    selectWindow(imageTitle);
    run("Select All");
    run("Copy");
    selectWindow("ROI_Reference");
    run("Paste");
    
    run("Line Width...", "line=3");
    
    roiColors = newArray("#E9DF00", "#01FDF6", "#16C47F", "#FEFCFD", "#FB9F89", "#CBBAED", "#CAE9FF", "#8000FF", "#00FF80", "#FF0080");
    
    for (roi = 0; roi < roiManager("count"); roi++) {
        roiManager("select", roi);
        roiName = Roi.getName();
        
        colorIndex = roi % roiColors.length;
        color = roiColors[colorIndex];
        
        r = parseInt(substring(color, 1, 3), 16);
        g = parseInt(substring(color, 3, 5), 16);
        b = parseInt(substring(color, 5, 7), 16);
        
        setForegroundColor(r, g, b);
        run("Draw", "slice");
        
        setFont("SansSerif", 14, "bold");
        setColor(r, g, b);
        
        Roi.getCoordinates(xpoints, ypoints);
        xSum = 0;
        ySum = 0;
        for (p = 0; p < xpoints.length; p++) {
            xSum += xpoints[p];
            ySum += ypoints[p];
        }
        xCenter = xSum / xpoints.length;
        yCenter = ySum / ypoints.length;
        
        Overlay.drawString(roiName, xCenter, yCenter);
    }
    
    Overlay.show;
    
    run("Line Width...", "line=1");
    
    safeFilename = replace(filename, "[^a-zA-Z0-9_\\-]", "_");
    savePath = outputDir + safeFilename + "_roi_position.tif";
    
    if (lengthOf(savePath) > 250) {
        safeFilename = substring(safeFilename, 0, 30);
        savePath = outputDir + safeFilename + "_roi_position.tif";
    }
    
    print("Saving ROI position image to: " + savePath);
    
    run("Bio-Formats Exporter", "save=[" + savePath + "] compression=Uncompressed");
    
    if (!File.exists(savePath)) {
        print("Bio-Formats export failed, trying regular save...");
        saveAs("Tiff", savePath);
    }
    
    close();
    
    selectWindow(imageTitle);
}

function processROI(roi, roiName, roiArea, roiMask, filename, outputDir, sequenceNumber) {
    print("\n>>> Processing ROI: " + roiName);
    
    totalNuclei = 0;
    
    // NEW: Process DAPI only if enabled
    if (useDAPI) {
        // Apply ROI mask to DAPI
        imageCalculator("AND create", "DAPI_mask", roiMask);
        rename("DAPI_mask_ROI_" + roi);
        
        // Count DAPI nuclei
        selectWindow("DAPI_mask_ROI_" + roi);
        roiManager("reset");
        run("Analyze Particles...", "size=" + minNucleusSize + "-" + maxNucleusSize + 
            " circularity=" + nucleusCircularity + "-1.00 show=Nothing display exclude add");
        
        totalNuclei = roiManager("count");
        print("Total DAPI detected in " + roiName + ": " + totalNuclei);
        
        // Create DAPI binary mask
        selectWindow("DAPI_mask_ROI_" + roi);
        run("Create Selection");
        if (selectionType() != -1) {
            newImage("DAPI_binary_" + roi, "8-bit black", getWidth(), getHeight(), 1);
            run("Restore Selection");
            setForegroundColor(255, 255, 255);
            run("Fill", "slice");
            run("Select None");
        } else {
            selectWindow("DAPI_mask_ROI_" + roi);
            run("Duplicate...", "title=DAPI_binary_" + roi);
        }
    }
    
    // Apply ROI mask to c-Fos
    imageCalculator("AND create", "cFos_mask", roiMask);
    rename("cFos_mask_ROI_" + roi);
    
    roiManager("reset");
    
    // Detect c-Fos objects
    selectWindow("cFos_mask_ROI_" + roi);
    
    run("Analyze Particles...", "size=" + minCfosSize + "-" + maxCfosSize + 
        " circularity=" + cFosCircularity + "-1.00 show=Nothing exclude add");
    
    cFosObjectCount = roiManager("count");
    
    cFosPosX = newArray(cFosObjectCount);
    cFosPosY = newArray(cFosObjectCount);
    validCFosObjects = newArray(cFosObjectCount);
    validCFosCount = 0;
    
    // NEW: Check overlap with DAPI only if enabled
    if (useDAPI) {
        // Check each c-Fos object for DAPI overlap
        for (i=0; i<cFosObjectCount; i++) {
            roiManager("select", i);
            
            List.setMeasurements;
            cFosArea = List.getValue("Area");
            
            selectWindow("DAPI_binary_" + roi);
            roiManager("select", i);
            
            List.setMeasurements;
            mean = List.getValue("Mean");
            overlappingPercentage = mean * 100 / 255;
            
            if (overlappingPercentage >= minOverlap) {
                Roi.getBounds(x, y, width, height);
                cFosPosX[validCFosCount] = x + (width/2);
                cFosPosY[validCFosCount] = y + (height/2);
                
                validCFosObjects[i] = 1;
                validCFosCount++;
            } else {
                validCFosObjects[i] = 0;
            }
        }
        
        cFosPositive = validCFosCount;
        
        if (cFosPositive > 0) {
            print("Found " + cFosObjectCount + " total c-Fos objects in " + roiName);
            print("After DAPI overlap filtering (" + minOverlap + "% minimum overlap): " + cFosPositive + " valid objects");
        } else {
            print("No c-Fos positive cells detected in " + roiName + " after DAPI overlap filtering.");
        }
    } else {
        // Without DAPI, count all c-Fos objects as positive
        for (i=0; i<cFosObjectCount; i++) {
            roiManager("select", i);
            Roi.getBounds(x, y, width, height);
            cFosPosX[i] = x + (width/2);
            cFosPosY[i] = y + (height/2);
            validCFosObjects[i] = 1;
        }
        
        validCFosCount = cFosObjectCount;
        cFosPositive = validCFosCount;
        
        print("Found " + cFosPositive + " c-Fos objects in " + roiName + " (no DAPI filtering)");
    }
    
    // Calculate density
    cFosDensity = cFosPositive / roiArea;
    
    // Store batch results
    if (choice == "Directory") {
        allNumbers[allNumbers.length] = sequenceNumber;
        allRois[allRois.length] = roiName;
        allFileNames[allFileNames.length] = filename;
        allTotalDapi[allTotalDapi.length] = totalNuclei;
        allCFosCells[allCFosCells.length] = cFosPositive;
        allROIAreas[allROIAreas.length] = roiArea;
        allCFosDensity[allCFosDensity.length] = cFosDensity;
        
        print("  Added to summary: " + sequenceNumber + ", " + roiName + ", " + cFosPositive);
    }
    
    // Create visualization
    if (saveOverlay) {
        // Create visualization based on available channels
        if (useDAPI) {
            selectWindow("DAPI");
            run("Duplicate...", "title=DAPI_viz_" + roi);
            
            selectWindow("cFos_processed");
            run("Duplicate...", "title=cFos_viz_" + roi);
            
            newImage("GreenChannel_" + roi, "8-bit black", getWidth(), getHeight(), 1);
            
            setForegroundColor(255, 255, 255);
            run("Line Width...", "line=0.4");
            
            selectWindow("DAPI_mask_ROI_" + roi);
            run("Create Selection");
            if (selectionType() != -1) {
                selectWindow("GreenChannel_" + roi);
                run("Restore Selection");
                run("Draw", "slice");
                run("Select None");
            }
            
            // Merge with DAPI visualization
            run("Merge Channels...", "c1=cFos_viz_" + roi + " c2=GreenChannel_" + roi + " c3=DAPI_viz_" + roi + " create");
            rename("Merged_Result_" + roi);
        } else {
            // Without DAPI, create simpler visualization
            selectWindow("cFos_processed");
            run("Duplicate...", "title=cFos_viz_" + roi);
            
            // Convert to RGB for overlay
            run("RGB Color");
            rename("Merged_Result_" + roi);
        }
        
        // Add overlay markers
        Overlay.remove;
        
        // Add ROI outline
        selectWindow(roiMask);
        run("Create Selection");
        selectWindow("Merged_Result_" + roi);
        run("Restore Selection");
        run("Properties... ", "stroke=yellow width=1.2");
        Overlay.addSelection;
        run("Select None");
        
        // Add c-Fos markers
        if (cFosPositive > 0) {
            for (i=0; i<cFosPositive; i++) {
                crossSize = 6;
                
                makeLine(cFosPosX[i]-crossSize/2, cFosPosY[i], cFosPosX[i]+crossSize/2, cFosPosY[i]);
                run("Properties... ", "stroke=yellow width=" + cFosMarkerWidth);
                Overlay.addSelection;
                
                makeLine(cFosPosX[i], cFosPosY[i]-crossSize/2, cFosPosX[i], cFosPosY[i]+crossSize/2);
                run("Properties... ", "stroke=yellow width=" + cFosMarkerWidth);
                Overlay.addSelection;
            }
        }
        
        Overlay.show;
        
        safeFilename = replace(filename, "[^a-zA-Z0-9_\\-]", "_");
        safeRoiName = replace(roiName, "[^a-zA-Z0-9_\\-]", "_");
        savePath = outputDir + safeFilename + "_" + safeRoiName + "_analyzed.tif";
        
        if (lengthOf(savePath) > 250) {
            maxFileLen = 20;
            maxRoiLen = 15;
            if (lengthOf(safeFilename) > maxFileLen) {
                safeFilename = substring(safeFilename, 0, maxFileLen);
            }
            if (lengthOf(safeRoiName) > maxRoiLen) {
                safeRoiName = substring(safeRoiName, 0, maxRoiLen);
            }
            savePath = outputDir + safeFilename + "_" + safeRoiName + "_analyzed.tif";
        }
        
        print("Saving analyzed image to: " + savePath);
        saveAs("Tiff", savePath);
    }
    
    // Save to log
    if (choice == "Directory") {
        appendToLog = filename + "\t" + roiName + "\t" + cFosPositive + "\t" + roiArea;
        File.append(appendToLog, outputDir + "analysis_log.txt");
        
        selectWindow("Batch Summary");
        Table.set("Filename", currentTableRow, filename);
        Table.set("ROI Name", currentTableRow, roiName);
        Table.set("c-Fos+ Cells", currentTableRow, cFosPositive);
        Table.set("ROI Area (px²)", currentTableRow, roiArea);
        Table.set("Density (cells/px²)", currentTableRow, cFosDensity);
        Table.update;
    } else {
        selectWindow("Detailed_Results");
        rowIndex = Table.size;
        Table.set("ROI Name", rowIndex, roiName);
        
        if (useDAPI) {
            Table.set("Total DAPI", rowIndex, totalNuclei);
        }
        
        Table.set("c-Fos+ Cells", rowIndex, cFosPositive);
        Table.set("ROI Area (px²)", rowIndex, roiArea);
        Table.set("Density (cells/px²)", rowIndex, cFosDensity);
        Table.update;
    }
    
    // Update summary table
    selectWindow("Summary_Results");
    
    cleanRoiName = replace(roiName, "\n", "");
    cleanRoiName = replace(cleanRoiName, "\r", "");
    cleanRoiName = String.trim(cleanRoiName);
    
    columnExists = false;
    headings = split(Table.headings, "\t");
    for (h=0; h<headings.length; h++) {
        if (headings[h] == cleanRoiName) {
            columnExists = true;
            break;
        }
    }
    
    if (!columnExists) {
        zeros = newArray(Table.size);
        for (z=0; z<Table.size; z++) zeros[z] = 0;
        Table.setColumn(cleanRoiName, zeros);
    }
    
    // Update metrics
    for (i=0; i<Table.size; i++) {
        metric = Table.getString("Metric", i);
        
        if (useDAPI && metric == "Total DAPI") {
            Table.set(cleanRoiName, i, totalNuclei);
        } else if (metric == "Total c-Fos Objects") {
            Table.set(cleanRoiName, i, cFosObjectCount);
        } else if (metric == "c-Fos+ Cells") {
            Table.set(cleanRoiName, i, cFosPositive);
        } else if (metric == "ROI Area (px²)") {
            Table.set(cleanRoiName, i, roiArea);
        } else if (metric == "c-Fos+ Density") {
            Table.set(cleanRoiName, i, cFosDensity);
        } else if (useDAPI && metric == "Min DAPI Overlap (%)") {
            Table.set(cleanRoiName, i, minOverlap);
        }
    }
    Table.update;
}

function getDateTime() {
    MonthNames = newArray("Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec");
    DayNames = newArray("Sun", "Mon","Tue","Wed","Thu","Fri","Sat");
    getDateAndTime(year, month, dayOfWeek, dayOfMonth, hour, minute, second, msec);
    TimeString = DayNames[dayOfWeek]+" ";
    if (dayOfMonth<10) {TimeString = TimeString+"0";}
    TimeString = TimeString+dayOfMonth+"-"+MonthNames[month]+"-"+year+" ";
    if (hour<10) {TimeString = TimeString+"0";}
    TimeString = TimeString+hour+":";
    if (minute<10) {TimeString = TimeString+"0";}
    TimeString = TimeString+minute+":";
    if (second<10) {TimeString = TimeString+"0";}
    TimeString = TimeString+second;
    return TimeString;
}