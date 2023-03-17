//
//  ControlViewController.m
//  Portkey
//
//  Created by Kendall Toerner on 4/8/16.
//  Copyright © 2016 Elovation Design. All rights reserved.
//

#import "ControlViewController.h"
#import "UARTPeripheral.h"
#import <CoreBluetooth/CoreBluetooth.h>
#import "Spark-SDK.h"

@import MapKit;

@interface ControlViewController () <CLLocationManagerDelegate, CBCentralManagerDelegate, UARTPeripheralDelegate, UITableViewDelegate, CBPeripheralDelegate>

@property (strong, nonatomic) IBOutlet UILabel *remotestatus;
@property (strong, nonatomic) IBOutlet UILabel *bluetoothstatus;
@property (strong, nonatomic) IBOutlet UIView *unlockbutton;
@property (strong, nonatomic) IBOutlet UILabel *unlockbutton_text;
@property (strong, nonatomic) IBOutlet UILabel *bluetoothrssi;

@end

@implementation ControlViewController

@synthesize remotestatus;
@synthesize bluetoothstatus;
@synthesize bluetoothrssi;
@synthesize unlockbutton;
@synthesize unlockbutton_text;

//Gestures
UITapGestureRecognizer *unlockTapRecognizer;

//BLE
CBPeripheral *peripheral;
CBCentralManager    *cm;
UARTPeripheral      *currentPeripheral;

CLLocationManager *locationmanager;

NSTimer *resetunlock;
NSTimer *verifyRemoteConnectionTimer;
NSTimer *verifyBLERSSITimer;

//Variables
bool locked = true;
bool lockchanging = false;

SparkDevice *portkeyphoton;

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    //First Initializations
    [self firstInits];
    
    //Search for Portkey
    [self searchBLE];
    
    //Search for Wifi Portkey Connection
    [self initParticle];
    
    //Define UI Frames
    [self createFrames];
    
    //Create UI
    [self createUI];
}

-(void)firstInits
{
    //Initialize BLE CM
    cm = [[CBCentralManager alloc] initWithDelegate:self queue:nil];
    
    //Setup Notifications
    UIUserNotificationType types = (UIUserNotificationType) (UIUserNotificationTypeBadge | UIUserNotificationTypeSound | UIUserNotificationTypeAlert);
    UIUserNotificationSettings *mySettings = [UIUserNotificationSettings settingsForTypes:types categories:nil];
    [[UIApplication sharedApplication] registerUserNotificationSettings:mySettings];
    
    //Location manager
    [self askForLocationPermissions];
    locationmanager = [[CLLocationManager alloc] init];
    locationmanager.delegate = self;
    
    //Initialize gestures
    unlockTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(unlockTapGesture:)];
    
    //Add Gestures
    [unlockbutton addGestureRecognizer:unlockTapRecognizer];
}

-(void)createFrames
{
}

-(void)createUI
{
    unlockbutton.backgroundColor = [UIColor colorWithRed:0.5 green:0.5 blue:0.5 alpha:1];
    unlockbutton_text.textColor = [UIColor colorWithRed:0.65 green:0.65 blue:0.65 alpha:1];
    
    bluetoothrssi.text = @"";
}

-(void)receiveCommand:(NSString*)command
{
}

/*-------------------*/
/*---REMOTE ACCESS---*/
/*-------------------*/

-(void)initParticle
{
    [[SparkCloud sharedInstance] loginWithUser:@"kendall@hotmail.com" password:@"pass135" completion:^(NSError *error) {
        if (!error)
        {
            NSLog(@"Logged in to Particle Cloud");
            
            [self getParticleDevices];
        }
        else
        {
            NSLog(@"Partcile Cloud: Wrong credentials or no internet connectivity, please try again");
        }
    }];
}

-(void)getParticleDevices
{
    [[SparkCloud sharedInstance] getDevices:^(NSArray *sparkDevices, NSError *error) {
        //NSLog(@"%@",sparkDevices.description); // print all devices claimed to user
        
        for (SparkDevice *device in sparkDevices)
        {
            if ([device.name isEqualToString:@"Portkey"])
            {
                portkeyphoton = device;
                [self checkRemoteConnection];
                verifyRemoteConnectionTimer = [NSTimer scheduledTimerWithTimeInterval:10 target:self selector:@selector(checkRemoteConnection) userInfo:nil repeats:true];
                return;
            }
        }
    }];
    
}

-(void)checkRemoteConnection
{
    [portkeyphoton refresh:^(NSError * _Nullable error) {
        if (!error)
        {
            if (portkeyphoton.connected)
            {
                //Check Lock Status
                [self checkLockStatus];
                
                remotestatus.text = @"Online";
                remotestatus.textColor = [UIColor colorWithRed:0 green:1 blue:0 alpha:1];
                
                unlockbutton_text.textColor = [UIColor colorWithWhite:1 alpha:1];
                [UIView animateWithDuration:0.5 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
                    unlockbutton.backgroundColor = [UIColor colorWithRed:0 green:.55 blue:1 alpha:1];
                }completion:nil];
            }
            else
            {
                remotestatus.text = @"Offline";
                remotestatus.textColor = [UIColor colorWithRed:1 green:.2 blue:0 alpha:1];
                NSArray *connectedPeripherals = [cm retrieveConnectedPeripheralsWithServices:@[UARTPeripheral.uartServiceUUID]];
                if ([connectedPeripherals count] > 0)
                {
                    //Connected via bluetooth, keep button functionality
                }
                else
                {
                    //Not connected to Portkey via Wifi or Bluetooth
                    unlockbutton.backgroundColor = [UIColor colorWithRed:1 green:.2 blue:0 alpha:1];
                    unlockbutton_text.textColor = [UIColor colorWithWhite:1 alpha:1];
                }
            }
        }
        else
        {
            remotestatus.text = @"*Error*";
            remotestatus.textColor = [UIColor colorWithRed:1 green:.2 blue:0 alpha:1];
            unlockbutton.backgroundColor = [UIColor colorWithRed:1 green:.2 blue:0 alpha:1];
            unlockbutton_text.textColor = [UIColor colorWithWhite:1 alpha:1];
        }
    }];
}

-(id)getParticleVariable:(NSString*)variable
{
    __block id varresult;
    [portkeyphoton getVariable:variable completion:^(id result, NSError *error) {
        if (!error) {
            varresult = result;
        }
        else {
            NSLog(@"Failed reading variable from Particle Cloud");
        }
    }];
    return varresult;
}

-(bool)sendPartileFunctionCommand:(NSString*)command
{
    __block bool success;
    
    [portkeyphoton callFunction:@"performCmd" withArguments:@[command] completion:^(NSNumber *resultCode, NSError *error) {
        if (!error)
        {
            NSLog(@"Particle Function Call Successful");
            success = true;
        }
        else
        {
            NSLog(@"Particle Function Call Failed");
            success = false;
        }
    }];
    return success;
}

-(void)lock
{
    NSArray *connectedPeripherals = [cm retrieveConnectedPeripheralsWithServices:@[UARTPeripheral.uartServiceUUID]];
    if ([connectedPeripherals count] > 0)
    {
        [self sendDataBLE:@"lock"];
        
        locked = true;
        unlockbutton_text.text = @"Unlock";
        lockchanging = false;
    }
    
    if (!portkeyphoton.connected)
    {
        //Lock Unsuccessful
        unlockbutton.backgroundColor = [UIColor colorWithRed:1 green:.2 blue:0 alpha:1];
        unlockbutton_text.textColor = [UIColor colorWithWhite:1 alpha:1];
        
        [self checkRemoteConnection];
        return;
    }
    
    [portkeyphoton callFunction:@"performCmd" withArguments:@[@"lock"] completion:^(NSNumber *resultCode, NSError *error) {
        if (!error)
        {
            NSLog(@"Particle Function Call Successful");
            //Unlock Successful
            unlockbutton.backgroundColor = [UIColor colorWithRed:0 green:1 blue:0 alpha:1];
            unlockbutton_text.textColor = [UIColor colorWithWhite:1 alpha:1];
            
            resetunlock = [NSTimer scheduledTimerWithTimeInterval:.5 target:self selector:@selector(resetUnlock) userInfo:nil repeats:false];
            
            locked = true;
            unlockbutton_text.text = @"Unlock";
            lockchanging = false;
        }
        else
        {
            NSLog(@"Particle Function Call Failed");
            //Unlock Unsuccessful
            unlockbutton.backgroundColor = [UIColor colorWithRed:1 green:.2 blue:0 alpha:1];
            unlockbutton_text.textColor = [UIColor colorWithWhite:1 alpha:1];
            
            [self checkRemoteConnection];
        }
    }];
}

-(void)unlock
{
    NSArray *connectedPeripherals = [cm retrieveConnectedPeripheralsWithServices:@[UARTPeripheral.uartServiceUUID]];
    if ([connectedPeripherals count] > 0)
    {
        [self sendDataBLE:@"unlock"];
        
        //Unlock Successful
        unlockbutton.backgroundColor = [UIColor colorWithRed:0 green:1 blue:0 alpha:1];
        unlockbutton_text.textColor = [UIColor colorWithWhite:1 alpha:1];
        
        resetunlock = [NSTimer scheduledTimerWithTimeInterval:.5 target:self selector:@selector(resetUnlock) userInfo:nil repeats:false];
        
        locked = false;
        unlockbutton_text.text = @"Lock";
        lockchanging = false;
        
        return;
    }
    
    if (!portkeyphoton.connected)
    {
        //Unlock Unsuccessful
        unlockbutton.backgroundColor = [UIColor colorWithRed:1 green:.2 blue:0 alpha:1];
        unlockbutton_text.textColor = [UIColor colorWithWhite:1 alpha:1];
        
        [self checkRemoteConnection];
        return;
    }
    
    [portkeyphoton callFunction:@"performCmd" withArguments:@[@"unlock"] completion:^(NSNumber *resultCode, NSError *error) {
        if (!error)
        {
            NSLog(@"Particle Function Call Successful");
            //Unlock Successful
            unlockbutton.backgroundColor = [UIColor colorWithRed:0 green:1 blue:0 alpha:1];
            unlockbutton_text.textColor = [UIColor colorWithWhite:1 alpha:1];
            
            resetunlock = [NSTimer scheduledTimerWithTimeInterval:.5 target:self selector:@selector(resetUnlock) userInfo:nil repeats:false];
            
            locked = false;
            unlockbutton_text.text = @"Lock";
            lockchanging = false;
        }
        else
        {
            NSLog(@"Particle Function Call Failed");
            //Unlock Unsuccessful
            unlockbutton.backgroundColor = [UIColor colorWithRed:1 green:.2 blue:0 alpha:1];
            unlockbutton_text.textColor = [UIColor colorWithWhite:1 alpha:1];
            
            [self checkRemoteConnection];
        }
    }];
        
}

-(void)resetUnlock
{
    [UIView animateWithDuration:1.5 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        unlockbutton.backgroundColor = [UIColor colorWithRed:0 green:.55 blue:1 alpha:1];
    }completion:nil];
}

-(void)checkLockStatus
{
    [portkeyphoton refresh:^(NSError * _Nullable error) {
        if (!error)
        {
            if (portkeyphoton.connected)
            {
                [portkeyphoton getVariable:@"locked" completion:^(id result, NSError *error) {
                    if (!error)
                    {
                        NSNumber *lockedValue = (NSNumber *)result;
                        if (lockedValue.integerValue == 0)
                        {
                            if (lockchanging)
                            {
                                if (locked != [lockedValue boolValue])
                                {
                                    locked = false;
                                    unlockbutton_text.text = @"Lock";
                                }
                                else [self lock];
                            }
                            else
                            {
                                locked = false;
                                unlockbutton_text.text = @"Lock";
                            }
                        }
                        else
                        {
                            if (lockchanging)
                            {
                                if (locked != [lockedValue boolValue])
                                {
                                    locked = true;
                                    unlockbutton_text.text = @"Unlock";
                                }
                                [self unlock];
                            }
                            else
                            {
                                locked = true;
                                unlockbutton_text.text = @"Unlock";
                            }
                        }
                    }
                    else NSLog(@"Failed reading temperature from Photon device");
                }];
            }
            else
            {
                NSArray *connectedPeripherals = [cm retrieveConnectedPeripheralsWithServices:@[UARTPeripheral.uartServiceUUID]];
                if ([connectedPeripherals count] > 0)
                {
                    //Connected via bluetooth, keep button functionality
                }
                else
                {
                    //Not connected to Portkey via Wifi or Bluetooth
                }
            }
        }
        else
        {
            remotestatus.text = @"*Error*";
            remotestatus.textColor = [UIColor colorWithRed:1 green:.2 blue:0 alpha:1];
            unlockbutton.backgroundColor = [UIColor colorWithRed:1 green:.2 blue:0 alpha:1];
            unlockbutton_text.textColor = [UIColor colorWithWhite:1 alpha:1];
        }
    }];
}


/*--------------------*/
/*-----BLUETOOTH------*/
/*--------------------*/

//Implement bluetooth connection

- (void)searchBLE
{
    //Search for first bluetooth device
    //Skip if already connected
    NSArray *connectedPeripherals = [cm retrieveConnectedPeripheralsWithServices:@[UARTPeripheral.uartServiceUUID]];
    if ([connectedPeripherals count] > 0)
        [self connectBLE:[connectedPeripherals objectAtIndex:0]];
    else
        [cm scanForPeripheralsWithServices:@[UARTPeripheral.uartServiceUUID]
                                   options:@{CBCentralManagerScanOptionAllowDuplicatesKey: [NSNumber numberWithBool:NO]}];
}

- (void)connectBLE:(CBPeripheral*)peripheral
{
    //Clear pending connections
    [cm cancelPeripheralConnection:peripheral];
    
    //Connect
    currentPeripheral = [[UARTPeripheral alloc] initWithPeripheral:peripheral delegate:self];
    [cm connectPeripheral:peripheral options:@{CBConnectPeripheralOptionNotifyOnDisconnectionKey: [NSNumber numberWithBool:YES]}];
    
    //Display connected and change button to disconnect
    bluetoothstatus.text = @"Connected";
    bluetoothstatus.textColor = [UIColor colorWithRed:0 green:1 blue:0 alpha:1];
    
    [UIView animateWithDuration:1.5 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        unlockbutton.backgroundColor = [UIColor colorWithRed:0 green:.55 blue:1 alpha:1];
    }completion:nil];
    
    verifyBLERSSITimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(checkBLERSSI) userInfo:nil repeats:true];
}

- (void)disconnectBLE
{
    //Disconnect Bluetooth LE device
    [cm cancelPeripheralConnection:currentPeripheral.peripheral];
    bluetoothstatus.text = @"Searching...";
    bluetoothstatus.textColor = [UIColor colorWithRed:1 green:0.9 blue:0 alpha:1];
    
    if (!portkeyphoton.connected)
    {
        unlockbutton.backgroundColor = [UIColor colorWithRed:1 green:.2 blue:0 alpha:1];
        unlockbutton_text.textColor = [UIColor colorWithWhite:1 alpha:1];
    }
    
    bluetoothrssi.text = @"";
}

- (void)sendDataBLE:(NSString*)data
{
    NSData *newData = [data dataUsingEncoding:NSUTF8StringEncoding];
    
    [currentPeripheral writeRawData:newData];
}

- (void)receiveDataBLE:(NSData*)newData
{
    //Capture incoming data
    char data[20];
    int dataLength = (int)newData.length;
    [newData getBytes:&data length:dataLength];
    
    //Convert to String
    NSString *command = [[NSString alloc] initWithBytes:data length:dataLength encoding:NSUTF8StringEncoding];
    
    //Perform command
    [self receiveCommand:command];
}

-(void)checkBLERSSI
{
    NSNumber *RSSI = [currentPeripheral getRSSI];
    
    double RSSIint = [RSSI doubleValue];
    double distance = RSSIint+40;
    if (distance > 0) distance = 0;
    distance = -distance;
    distance = (distance/6.5);
    distance = distance * 1.5;
    
    if (distance < 10) bluetoothrssi.text = [NSString stringWithFormat:@"%.f ft",distance];
    else bluetoothrssi.text = @"10+ ft";
}

/*--------------------------*/
/*-----Location Manager-----*/
/*--------------------------*/

-(void)askForLocationPermissions
{
    if ([locationmanager respondsToSelector:@selector(requestAlwaysAuthorization)])
        [locationmanager requestAlwaysAuthorization];
    locationmanager.desiredAccuracy = kCLLocationAccuracyBest;
    //[locationmanager startUpdatingLocation];
}

/*-----------------------------*/
/*-----BLUETOOTH DELEGATE------*/
/*-----------------------------*/

- (void) centralManagerDidUpdateState:(CBCentralManager*)central
{
    if (central.state == CBCentralManagerStatePoweredOn)
    {
        //respond to powered on
        [self searchBLE];
    }
    
    else if (central.state == CBCentralManagerStatePoweredOff)
    {
        //respond to powered off
    }
    
}

- (void) centralManager:(CBCentralManager*)central didDiscoverPeripheral:(CBPeripheral*)peripheral advertisementData:(NSDictionary*)advertisementData RSSI:(NSNumber*)RSSI
{
    [cm stopScan];
    
    [self connectBLE:peripheral];
}


- (void) centralManager:(CBCentralManager*)central didConnectPeripheral:(CBPeripheral*)peripheral
{
    if ([currentPeripheral.peripheral isEqual:peripheral])
    {
        if (peripheral.services) [currentPeripheral peripheral:peripheral didDiscoverServices:nil];
        else [currentPeripheral didConnect];
        
        bluetoothstatus.text = @"Connected";
        bluetoothstatus.textColor = [UIColor colorWithRed:0 green:1 blue:0 alpha:1];
        
        unlockbutton_text.textColor = [UIColor colorWithWhite:1 alpha:1];
        
        //[self sendNotification:@"BLE Data Connected!"];
    }
}


- (void) centralManager:(CBCentralManager*)central didDisconnectPeripheral:(CBPeripheral*)peripheral error:(NSError*)error
{
    if ([currentPeripheral.peripheral isEqual:peripheral])
    {
        [currentPeripheral didDisconnect];
        bluetoothstatus.text = @"Searching...";
        bluetoothstatus.textColor = [UIColor colorWithRed:1 green:0.9 blue:0 alpha:1];
        [self searchBLE];
        
        if (!portkeyphoton.connected)
        {
            unlockbutton.backgroundColor = [UIColor colorWithRed:1 green:.2 blue:0 alpha:1];
            unlockbutton_text.textColor = [UIColor colorWithWhite:1 alpha:1];
        }
        
        [verifyBLERSSITimer invalidate];
        
        bluetoothrssi.text = @"";
        
        //[self sendNotification:@"BLE Data Disconnected!"];
    }
}

- (void)didReadHardwareRevisionString:(NSString*)string
{
    //Once hardware revision string is read, connection is complete
}

- (void)uartDidEncounterError:(NSString*)error
{
    //Error happened
}

- (void)didReceiveData:(NSData*)newData
{
    [self receiveDataBLE:newData];
}

-(void)updateBLERSSI:(NSNumber *)RSSI
{
    
}


-(void)unlockTapGesture:(UITapGestureRecognizer*)tapGestureRecognizer
{
    //CGPoint taplocation = [tapGestureRecognizer locationInView:menu];
    
    [UIView animateWithDuration:.1 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        unlockbutton.backgroundColor = [UIColor colorWithRed:1 green:.8 blue:0 alpha:1];
        unlockbutton_text.textColor = [UIColor colorWithWhite:0 alpha:1];
    }completion:nil];
    
    lockchanging = true;
    
    [self checkLockStatus];
}

/*----------------------------*/
/*--------NOTIFICATIONS-------*/
/*----------------------------*/

- (void)sendNotification:(NSString*)message
{
    UILocalNotification *localNotification = [[UILocalNotification alloc] init];
    localNotification.fireDate = [NSDate dateWithTimeIntervalSinceNow:0];
    localNotification.alertBody = message;
    localNotification.timeZone = [NSTimeZone defaultTimeZone];
    //localNotification.applicationIconBadgeNumber = [[UIApplication sharedApplication] applicationIconBadgeNumber] + 1;
    [[UIApplication sharedApplication] scheduleLocalNotification:localNotification];
}

/*---------------------------------*/
/*--------TABLEVIEW DELEGATE-------*/
/*---------------------------------*/


- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

@end
