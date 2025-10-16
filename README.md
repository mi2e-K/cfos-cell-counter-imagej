# c-Fos Cell Counter for ImageJ

## Overview

This ImageJ macro provides semi-automated analysis of c-Fos expression in fluorescence microscopy images. It's designed to quantify neuronal activation by counting c-Fos-positive cells, with optional DAPI colocalization to ensure nuclear localization.

### Key Features

- **Channel Configuration**: Choose any channel (red, green, or blue) for c-Fos and DAPI
- **Optional DAPI Analysis**: Enable/disable DAPI colocalization checking
- **Multi-ROI Support**: Analyze multiple regions of interest in a single image
- **Batch Processing**: Process entire directories of images automatically
- **Interactive Thresholding**: Manual adjustment or automatic thresholding options
- **ROI Configuration**: Import/export ROI settings for consistency across analyses

---

## Requirements

### Software
- **ImageJ** or **Fiji** (recommended)
- **CLAHE plugin** for ImageJ

### Input Files
- 2D fluorescence microscopy images in **TIF format**
- Multi-channel images with c-Fos signal (and optionally DAPI)

---

## Installation

### 1. Install ImageJ/Fiji
Download [Fiji](https://fiji.sc/) or [ImageJ](https://imagej.net/ij/download.html).

### 2. Install CLAHE Plugin
1. Download the CLAHE plugin from: https://imagej.net/ij/plugins/clahe/index.html
2. Drag and drop `CLAHE_.class` onto the "ImageJ" window.
3. Restart ImageJ/Fiji

### 3. Install the Macro
1. Download `cFosCounting_mk.ijm` from this repository
2. In ImageJ/Fiji: **Plugins → Macros → Install...** and select the macro file
3. Or run directly: **Plugins → Macros → Run...** and select the file

---

## Usage

### Quick Start

1. **Launch the macro**: Plugins → Macros → Run → `cFosCounting_mk.ijm`
2. **Configure channels**: Select which channel contains c-Fos and DAPI
3. **Choose processing mode**: Single image or directory batch processing
4. **Define ROIs**: Draw regions of interest when prompted
5. **Adjust threshold**: (If manual mode) Fine-tune detection threshold
6. **Review results**: Check output CSV files and overlay images

### Detailed Workflow

#### 1. Channel Configuration
- **c-Fos channel**: Select Red, Green, or Blue based on your imaging setup
- **Use DAPI**: Check this to enable colocalization analysis
- **DAPI channel**: Select the channel containing DAPI staining

#### 2. Analysis Mode
- **Single Image**: Analyze one image at a time
- **Directory**: Batch process multiple images

#### 3. ROI Settings
- **Enable multiple ROI analysis**: Check to analyze multiple regions per image
- **Number of ROIs**: Specify how many regions to define
- **Import ROI settings**: Load previously saved ROI configurations
- **Export ROI settings**: Save current ROI setup for reuse

#### 4. Image Preprocessing
- **Background subtraction radius**: Rolling ball radius (default: 100)
- **CLAHE parameters**:
  - Block size: 16
  - Histogram bins: 256
  - Max slope: 2.0

#### 5. Detection Parameters

**DAPI Detection** (if enabled):
- Min nucleus size: 50 pixels
- Max nucleus size: 500 pixels
- Circularity: 0.5-1.0

**c-Fos Detection**:
- Threshold method: Manual, Automatic (Yen), or Automatic (RenyiEntropy)
- Skip manual adjustment: For fully automatic processing
- Min overlap with DAPI: 40% (if DAPI enabled)
- Min c-Fos size: 30 pixels
- Max c-Fos size: 250 pixels
- Circularity: 0.4-1.0

#### 6. Visualization Options
- **DAPI outline color**: Default green
- **Save overlay images**: Annotated images showing detections
- **Save ROI position reference**: Image showing ROI locations

---

## Output Files

### For Single Image Analysis

- `[filename]_result.csv`: Summary table with metrics for each ROI
- `[filename]_[ROI]_analyzed.tif`: Overlay images with detected cells marked
- `[filename]_roi_position.tif`: Reference image showing ROI locations

### For Batch Processing

**In `Results/` subdirectory:**
- `analysis_log.txt`: Processing log with parameters and results
- `batch_summary.csv`: Summary of all processed images
- `[ID]_[region]_cfos_summary.csv`: Comprehensive summary organized by sample ID and region
- Individual analyzed images for each ROI
- ROI position references

### Results Table Columns

When DAPI is enabled:
- ROI Name
- Total DAPI Nuclei
- c-Fos+ Cells
- ROI Area (px²)
- Density (cells/px²)

Without DAPI:
- ROI Name
- c-Fos+ Cells
- ROI Area (px²)
- Density (cells/px²)

---

## File Naming Convention

The macro works best with files named in the format:
```
[ID]_[BrainRegion]_[Number].tif
```

Example: `1477_DRN_17.tif`
- ID: 1477
- Brain Region: DRN (Dorsal Raphe Nucleus)
- Sequence: 17

---

## Configuration Files

### ROI Settings (JSON)
Save and reuse ROI configurations:
```json
{
  "roiCount": 2,
  "roiNames": [
    "DRN",
    "PAG"
  ]
}
```

### Analysis Configuration
The macro automatically saves your settings to `cfos_config.json` in the working directory for quick reuse.

---

## License

MIT License

---

## Citation

If you use this macro in your research, please cite it appropriately and consider citing:

- [ImageJ](https://www.nature.com/articles/nmeth.2089): Schneider et al. (2012)
- [Fiji](https://www.nature.com/articles/nmeth.2019): Schindelin et al. (2012)
