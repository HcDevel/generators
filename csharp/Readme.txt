This zip contains a C# library (.dll) for all Tinkerforge Bricks and Bricklets
(Tinkerforge.dll), the source of the DLL (in source/) and all available C#
examples (in examples/).

The library has been compiled with:

gmcs /optimize /target:library /out:Tinkerforge.dll source/Tinkerforge/*.cs

The library can be used without any further extensions. As an example lets
compile the configuration example of the Stepper Brick.

For this we create a folder and copy the Tinkerforge.dll and the
examples/Brick/Stepper/ExampleConfiguration.cs into this folder.

example_folder/
 -> Tinkerforge.dll
 -> ExampleConfiguration.cs

In this folder we can now call the C# compiler with the following parameters
(1. Windows and 2. Linux/Mac OS (Mono))

1.) csc.exe       /target:exe /out:Example.exe /reference:Tinkerforge.dll ExampleConfiguration.cs
2.) /usr/bin/gmcs /target:exe /out:Example.exe /reference:Tinkerforge.dll ExampleConfiguration.cs

Or, alternatively add the DLL and the Example in an C# development environment
of your choice (such as Visual Studio or Mono Develop).

Documentation for the API can be found at http://www.tinkerforge.com/en/doc/index.html
