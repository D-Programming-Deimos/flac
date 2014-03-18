Windows notes
=============

On Windows to link against the libFLAC DLL you will need an import library.

Use coffimplib to convert the COFF libFLAC.lib import library to an OMF import library (using implib doesn't work properly).
