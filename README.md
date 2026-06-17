# KrustOS
Private OS, made on asembler.
------------------------------
Current status:building
--------------------------------------------
current time building KrustOS: 6months 7days
------------------------------
Things current aviable:
1.file system
2.terminal
3.working mouse tracking(only in QEMU)
4.working UI
-----------------------------
things currently unaviable:
1.working coursor from bootable device(right now in development)
2.Network/internet
3.saving files
4.change settings(in progress)
-----------------------------
More things will be changed with time.
----------------------------
If you want make bootable device with this OS, make sure you use Rufus, or other programs to use bootable device.
------------How to make bootable device with KrustOS with Rufus--------------------
1.download .img file of KrustOS
2.select your device where you want to flash .img file
3.In rufus click "select" button, and chose .img file of KrustOS
4.press ALT+I to disable ISO support
5.press "Start" to start flashing your usb drive
6.wait until flashing is complete.
7.Make sure CSM(Compatibility Support Module) is turned ON in BIOS
8.select boot drive with KrustOS flashed
9.Your in!
--------------------------How to compile it?--------------------------
If you want to compile it, you need QEMU and NASM.
1.download all files(kernel....)
2.make sure QEMU and NASM is located same path as in run.bat
3.make sure run.bat is located WITH all files in one folder.
4.run .bat file, it will automaticly compile base.img, and start OS.
5.Your in!
-------------------------------------------------------------------------
