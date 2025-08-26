# Asconv

CLI tool to convert images to ascii

## Build from source
Compiled binary in `zig-out/bin/asconv`

```
zig build -Doptimize=ReleaseFast
```
> Omit the `-Doptimize=ReleaseFast` flag for a debug build.

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
-i, --input       <path>                 Input file or url
-o, --out         <filename>             Path of the output file (omit to output to stdout)
-w, --width       <int>                  Width of wanted image
-h, --height      <int>                  Height of wanted image
-s, --scale       <float>                Scale the image to size
-f, --fit                                Scale the image to fit the terminal
-b, --brightness  <float>                Set brightness boost
-r, --reverse                            Reverse the charset
    --charset     <string>               Set custom characters to use
-c, --color       <?color256|truecolor>  Output with ANSI colors and set color range (default: color256)
-e, --edges       <?sobel|LoG|DoG>       Turn on edge detection and set algorithm (default: sobel)
    --sigma       <float>                Sigma value for DoG and LoG (default: 1.0)
-t, --time                               Show the time taken to convert the image
```
> Option arguments prefixed with `?` are optional.

