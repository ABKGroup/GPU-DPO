```
GPU-DPO/   
├── dpl 
│   ├── src                                       # Kernel function operators
│   │   ├── graphics                              # Graphics utilities
│   │   ├── infrastructure                        # Placement related objectives
│   │   ├── objective                             # GPU database construction
│   │   ├── optimization                          # Kernel operator implementations
│   │   │   ├── detailed_global.cu                # Global swap implementation
│   │   │   ├── detailed_mis.cu                   # MIS implementation
│   │   │   └── detailed_reorder.cu               # Local reordering implementation
│   │   └── util                                  # Utility related functions
│   ├── test
│   │   └── experiments                           # Experiments directory
│   │   │   ├── aes-multi-height-batched.tcl      # Tcl script for AES designs
│   │   │   ├── jpeg-multi-height-batched.tcl     # Tcl script for JPEG designs
│   │   │   └── mpgroup-multi-height-batched.tcl  # Tcl script for Mempool-Group designs
└── README.md                                     # Project documentation
```