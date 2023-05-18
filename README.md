# RaspberryPi-Factory-Reset

Factory Reset Your Raspbian OS
Description:
In the normal process to reset or restore the Raspberry Pi OS (Raspbian), you need to unplug the SD Card, format the card, re-write the OS image and plug it back again. If you are doing some testing or development, it can be a pain to go over this process again. This git contains the scripts using which you can create a Raspberry Pi OS image which has an option to factory reset the OS without plugging out the SD Card.

Usage:
Ready to use images:
These are based on the May 2020 version of the Raspberry Pi OS.
https://mega.nz/folder/akREwKKB#SNdASVnpzOaj7rPtrgPW_w

Prepare your own image by following the instructions given below on a linux based system
Image Versions	Free Space Required
Lite	10GB
Minimal Desktop	14GB
Full Desktop	25GB
Clone the git using:
git clone https://github.com/shivasiddharth/RaspberryPi-Factory-Reset  
Download your preferred image, unzip them and place them in the files directory.

Change directory using:

cd /home/${USER}/RaspberryPi-Factory-Reset/files/   
Make the script executable using:
sudo chmod +x ./create-factory-reset.sh  
Execute the script using:
sudo ./create-factory-reset.sh  
Copy the created image and write it to the SD Card and enjoy.
Command to factory reset:
sudo su -   
/boot/factory_reset --reset    
