# Asconv

Convert images to ascii

## Build from source
Compiled binary in `zig-out/bin/asconv`

```
zig build -Doptimize=ReleaseFast
```

## Usage
```
asconv [command] [options]
```
### Commands
```
ascii                                    Convert to ascii
size                                     Show size of the image
help                                     Print help
```

### Options
```
-i, --input        <path>                Input file or url
-o, --out          <filename>            Path of the output file (omit to output to stdout)
-w, --width        <int>                 Width of wanted image
-h, --height       <int>                 Height of wanted image
-s, --scale        <float>               Scale the image to size
-f, --fit                                Scale the image to fit the terminal
-b, --brightness   <float>               Set brightness boost
-r, --reverse                            Reverse the charset
-c, --color                              Output with ANSI colors
    --colormode    <color256|truecolor>  Set the range of colors used (default: color256)
-e, --edges                              Edge detection
    --alg          <sobel|LoG|DoG>       Algorithm for edge detection (default: sobel)
    --sigma        <float>               Sigma value for DoG and LoG (default: 1.0)
-t, --time                               Show the time taken to convert the image
```

