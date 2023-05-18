# RaspberryPi-Factory-Reset
# Factory Reset Your Raspbian OS    
### Description:   
In the normal process to reset or restore the Raspberry Pi OS (Raspbian), you need to unplug the SD Card, format the card, re-write the OS image and plug it back again.  If you are doing some testing or development, it can be a pain to go over this process again. This git contains the scripts using which you can create a Raspberry Pi OS image which has an option to factory reset the OS without plugging out the SD Card.
## Usage:   
1. Clone the git using:   
```
git clone https://github.com/shivasiddharth/RaspberryPi-Factory-Reset  
```   

2. Download your preferred live and recovery images, unzip them and place them in the files directory.   
2. Download your preferred image, unzip them and place them in the files directory.   

3. Change directory using:  
```   
cd /home/${USER}/RaspberryPi-Factory-Reset/files/   
```   
4. Make the script executable using:   
```   
sudo chmod +x ./create-factory-reset.sh  
```   
5. Execute the script using:   
```   
sudo ./create-factory-reset.sh  
```    
6. Copy the created image and write it to the SD Card and enjoy.    
7. Usage to factory reset:   
```  
sudo su -   
/boot/factory_reset --reset    
```    
