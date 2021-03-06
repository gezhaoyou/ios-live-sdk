//
//  UPLiveStreamerLivingVC.m
//  UPLiveSDKDemo
//
//  Created by DING FENG on 5/19/16.
//  Copyright © 2016 upyun.com. All rights reserved.
//

#import "UPLiveStreamerLivingVC.h"
#import "UPAVCapturer.h"
#import "AppDelegate.h"
#import <UPLiveSDK/UPLiveSDKConfig.h>

@interface UPLiveStreamerLivingVC () <UPAVCapturerDelegate>
{
    NSString *_videoOrientationDescription;
    NSString *_pushStreamStadusDescription;
}

@property (weak, nonatomic) IBOutlet UISwitch *filterSwitch;
@property (weak, nonatomic) IBOutlet UISwitch *streamingSwitch;
@property (weak, nonatomic) IBOutlet UISwitch *cameraSwitch;
@property (weak, nonatomic) IBOutlet UIView *panel;
@property (weak, nonatomic) IBOutlet UITextView *dashboard;
@property (nonatomic, strong) UIView *videoPreview;
@property (nonatomic, strong) UILabel *descriptionLabel;

@property (nonatomic, assign) CGFloat lastScale;

@property (nonatomic, assign) NSInteger filterCode;

@end

@implementation UPLiveStreamerLivingVC

- (void)viewDidLoad {
    self.view.backgroundColor = [UIColor whiteColor];
    
    //设置视频预览视图 videoPreview
    UIViewContentMode previewContentMode = UIViewContentModeScaleAspectFit;
    if (_settings.fullScreenPreviewOn) {
        previewContentMode = UIViewContentModeScaleAspectFill;
    }
    
    self.videoPreview = [[UPAVCapturer sharedInstance] previewWithFrame:[UIScreen mainScreen].bounds
                                                            contentMode:previewContentMode];
    self.videoPreview.backgroundColor = [UIColor blackColor];
    
    //横竖屏拍摄提示 label
    self.descriptionLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 100, 200, 44)];
    self.descriptionLabel.backgroundColor = [UIColor blackColor];
    self.descriptionLabel.alpha = 0.5;
    self.descriptionLabel.textColor = [UIColor whiteColor];
    
    switch (_settings.videoOrientation) {
        case AVCaptureVideoOrientationPortrait:
            _videoOrientationDescription = @"竖屏拍摄";
            break;
        case AVCaptureVideoOrientationPortraitUpsideDown:
            _videoOrientationDescription = @"竖屏拍摄";
            break;
        case AVCaptureVideoOrientationLandscapeRight:
            _videoOrientationDescription = @"横屏拍摄";
            break;
        case AVCaptureVideoOrientationLandscapeLeft:
            _videoOrientationDescription = @"横屏拍摄";
            break;
        default:
            break;
    }
    self.descriptionLabel.text = _videoOrientationDescription;
    [self.videoPreview  addSubview:self.descriptionLabel];
    [self.view insertSubview:self.videoPreview atIndex:0];
    
    //开启 debug 信息
    [UPLiveSDKConfig setLogLevel:UP_Level_error];

    //设置代理，采集状态推流信息回调
    [UPAVCapturer sharedInstance].delegate = self;
    
    //拍摄 zoom 手势
    UIPinchGestureRecognizer *pinchGestureRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self
                                                                                                 action:@selector(handlePinchGesture:)];
    [self.videoPreview addGestureRecognizer:pinchGestureRecognizer];
}

- (void)viewWillAppear:(BOOL)animated {
    self.filterSwitch.on = _settings.filter;
    self.streamingSwitch.on = _settings.streamingOn;
}

- (void)viewDidAppear:(BOOL)animated {
    [self start];
}

- (void)start {
    [[UPAVCapturer sharedInstance] stop];
    [UPAVCapturer sharedInstance].capturerPresetLevel = _settings.level;
    [UPAVCapturer sharedInstance].camaraPosition = _settings.camaraPosition;
    [UPAVCapturer sharedInstance].camaraTorchOn = _settings.camaraTorchOn;
    [UPAVCapturer sharedInstance].videoOrientation = _settings.videoOrientation;
    [UPAVCapturer sharedInstance].fps = _settings.fps;
    
//    [[UPAVCapturer sharedInstance] setFilterName:UPCustomFilter1977];
    //推流地址
    NSString *rtmpPushUrl = [NSString stringWithFormat:@"%@%@", _settings.rtmpServerPushPath, _settings.streamId];
    
    //计算 upToken
    NSString *upToken = [UPAVCapturer tokenWithKey:@"password"
                                            bucket:@"testlivesdk"
                                        expiration:86400
                                   applicationName:_settings.rtmpServerPushPath.lastPathComponent
                                        streamName:_settings.streamId];
    
    rtmpPushUrl = [NSString stringWithFormat:@"%@?_upt=%@", rtmpPushUrl, upToken];
    NSLog(@"rtmpPushUrl: %@", rtmpPushUrl);
    [UPAVCapturer sharedInstance].outStreamPath = rtmpPushUrl;
    /// 要调节成 16:9 的比例, 可以自行调整要裁剪的大小
    
    switch (_settings.level) {
        case UPAVCapturerPreset_480x360:
            [UPAVCapturer sharedInstance].capturerPresetLevelFrameCropRect = CGSizeMake(270, 480);
            break;
        case UPAVCapturerPreset_640x480:
            [UPAVCapturer sharedInstance].capturerPresetLevelFrameCropRect = CGSizeMake(360, 640);
            break;
        case UPAVCapturerPreset_1280x720:
            [UPAVCapturer sharedInstance].capturerPresetLevelFrameCropRect = CGSizeMake(720, 1280);
            break;
    }
    
    // [UPAVCapturer sharedInstance].capturerPresetLevelFrameCropRect = CGSizeMake(360, 640);
//    if ([UPAVCapturer sharedInstance].videoOrientation == AVCaptureVideoOrientationLandscapeRight
//        || [UPAVCapturer sharedInstance].videoOrientation == AVCaptureVideoOrientationLandscapeLeft) {
//        
//        [UPAVCapturer sharedInstance].capturerPresetLevelFrameCropRect = CGSizeMake(640, 360);
//    }
//    [UPAVCapturer sharedInstance].bitrate = 400000;
    /// 水印设置
//    CGSize size = [UIScreen mainScreen].bounds.size;
//    __block UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, size.width, 44)];
//    label.text = @"我是水印";
//    label.textAlignment = NSTextAlignmentRight;
//    
//    UIImageView *imgV = [[UIImageView alloc]initWithFrame:CGRectMake(size.width - 80, 44, 80, 60)];
//    imgV.image = [UIImage imageNamed:@"upyun_logo"];
//    
//    UIView *subView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, size.width, size.height)];
//    subView.backgroundColor = [UIColor clearColor];
//    [subView addSubview:label];
//    [subView addSubview:imgV];
//    [[UPAVCapturer sharedInstance] setWatermarkView:subView Block:^{
//        label.text = [NSString stringWithFormat:@"upyun:%@", [NSDate date]];
//    }];
    
    [UPAVCapturer sharedInstance].networkSateBlock = ^(int level) {
        if (level == 0) {
            NSLog(@"网络比较差");
        } else if (level == 1){
            NSLog(@"网络一般");
        } else {
            NSLog(@"网络良好");
        }
    };
    
    [[UPAVCapturer sharedInstance] start];

    [self updateDashboard];
}


- (IBAction)streamingSwitch:(id)sender {
//    [UPAVCapturer sharedInstance].streamingOn = ![UPAVCapturer sharedInstance].streamingOn;
//    
    UISwitch *item = sender;
    // self.dashboard.hidden = !item.on;
    
        if (_filterCode == UPCustomFilterHefe + 2) {
            _filterCode = 0;
        }
    
        if (_filterCode == UPCustomFilterHefe + 1) {
            [[UPAVCapturer sharedInstance] setFilter:nil];
        } else {
            [[UPAVCapturer sharedInstance] setFilterName:_filterCode];
        }
        _filterCode++;
    
}

- (IBAction)filterSwitch:(id)sender {
    UISwitch *item = sender;
    
    [UPAVCapturer sharedInstance].filterOn = item.on;
    
//    /// 音量增益的代码
//    NSLog(@"[UPAVCapturer sharedInstance].audioUnitRecorder.increaserRate %d", [UPAVCapturer sharedInstance].increaserRate);
//    [UPAVCapturer sharedInstance].increaserRate = [UPAVCapturer sharedInstance].increaserRate + 10;
    
    
//    if (_filterCode == UPCustomFilterHefe + 2) {
//        _filterCode = 0;
//    }
//    
//    if (_filterCode == UPCustomFilterHefe + 1) {
//        [[UPAVCapturer sharedInstance] setFilter:nil];
//    } else {
//        [[UPAVCapturer sharedInstance] setFilterName:_filterCode];
//    }
//    _filterCode++;
    
    
    
    // 美颜开关
//    [UPAVCapturer sharedInstance].filterOn = ![UPAVCapturer sharedInstance].filterOn;
//    if ([UPAVCapturer sharedInstance].audioUnitRecorder.increaserRate == 10) {
//        [UPAVCapturer sharedInstance].audioUnitRecorder.increaserRate = 1;
//    } else {
//        [UPAVCapturer sharedInstance].audioUnitRecorder.increaserRate = 10;
//    }
}

- (IBAction)cameraSwitch:(id)sender {
    

    /// 降噪功能是否开启
//    [UPAVCapturer sharedInstance].deNoise = ![UPAVCapturer sharedInstance].deNoise ;
    
//    /// 镜头切换的代码
    if ([UPAVCapturer sharedInstance].camaraPosition == AVCaptureDevicePositionBack) {
        [UPAVCapturer sharedInstance].camaraPosition = AVCaptureDevicePositionFront;
    } else {
        [UPAVCapturer sharedInstance].camaraPosition = AVCaptureDevicePositionBack;
    }
}

- (IBAction)stop:(id)sender {
//    [[UPAVCapturer sharedInstance] stop];
    [self dismissViewControllerAnimated:YES completion:^{
        [[UPAVCapturer sharedInstance] stop];
    }];
}


- (void)handlePinchGesture:(UIPinchGestureRecognizer *)sender {
    
    CGFloat scale = sender.scale;
    if (_lastScale == 0) {
        _lastScale = 1;
    }
    CGFloat newScale = _lastScale+scale-1;
    if (newScale >= 1 && newScale <= 3) {
        _lastScale = newScale;
        [UPAVCapturer sharedInstance].viewZoomScale = newScale;
    }
}

- (void)errorAlert:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^(){
        
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"推流错误，请检查网络重试，或者更换一个流id后重试"
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault
                                                              handler:^(UIAlertAction * action) {
                                                                  [self dismissViewControllerAnimated:YES completion:nil];
                                                              }];
        
        [alert addAction:defaultAction];
        [self presentViewController:alert animated:YES completion:nil];
    });
}

//将预览视图固定。
//拍摄开始后镜头方向便固定了，所以预览视图也需要固定。(效果类似系统自带 camera app）https://developer.apple.com/library/ios/qa/qa1890/_index.html
- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    self.videoPreview.center = CGPointMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds));
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        CGAffineTransform deltaTransform = coordinator.targetTransform;
        CGFloat deltaAngle = atan2f(deltaTransform.b, deltaTransform.a);
        
        CGFloat currentRotation = [[self.videoPreview.layer valueForKeyPath:@"transform.rotation.z"] floatValue];
        // Adding a small value to the rotation angle forces the animation to occur in a the desired direction, preventing an issue where the view would appear to rotate 2PI radians during a rotation from LandscapeRight -> LandscapeLeft.
        currentRotation += -1 * deltaAngle + 0.0001;
        [self.videoPreview.layer setValue:@(currentRotation) forKeyPath:@"transform.rotation.z"];
        
    } completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        // Integralize the transform to undo the extra 0.0001 added to the rotation angle.
        CGAffineTransform currentTransform = self.videoPreview.transform;
        currentTransform.a = round(currentTransform.a);
        currentTransform.b = round(currentTransform.b);
        currentTransform.c = round(currentTransform.c);
        currentTransform.d = round(currentTransform.d);
        self.videoPreview.transform = currentTransform;
    }];
}


#pragma mark UPAVCapturerDelegate

//采集状态
- (void)UPAVCapturer:(UPAVCapturer *)capturer capturerStatusDidChange:(UPAVCapturerStatus)capturerStatus {
    
    switch (capturerStatus) {
        case UPAVCapturerStatusStopped: {
            NSLog(@"===UPAVCapturerStatusStopped");
        }
            break;
        case UPAVCapturerStatusLiving: {
            NSLog(@"===UPAVCapturerStatusLiving");

        }
            break;
        case UPAVCapturerStatusError: {
            NSLog(@"===UPAVCapturerStatusError");
        }
            break;
        default:
            break;
    }
}

- (void)UPAVCapturer:(UPAVCapturer *)capturer capturerError:(NSError *)error {
    if (error) {
        NSString *s = [NSString stringWithFormat:@"%@", error];
        [self errorAlert:s];
    }
}

//推流状态
- (void)UPAVCapturer:(UPAVCapturer *)capturer pushStreamStatusDidChange:(UPPushAVStreamStatus)streamStatus {
    
    switch (streamStatus) {
        case UPPushAVStreamStatusClosed:
            NSLog(@"===UPPushAVStreamStatusClosed");
            _pushStreamStadusDescription = @"连接关闭";
            break;
        case UPPushAVStreamStatusConnecting:
            NSLog(@"===UPPushAVStreamStatusConnecting");
            _pushStreamStadusDescription = @"连接中...";
            break;
        case UPPushAVStreamStatusReady:
            _pushStreamStadusDescription = @"准备直播";
            NSLog(@"===UPPushAVStreamStatusReady");

            break;
        case UPPushAVStreamStatusPushing:
            NSLog(@"===UPPushAVStreamStatusPushing");
            _pushStreamStadusDescription = @"直播中...";
            self.descriptionLabel.text = @"竖屏拍摄";

            break;
        case UPPushAVStreamStatusError: {
            _pushStreamStadusDescription = @"连接错误";
            NSLog(@"===UPPushAVStreamStatusError");
        }
            break;
        default:
            break;
    }
    self.descriptionLabel.text = [NSString stringWithFormat:@"%@%@", _videoOrientationDescription, _pushStreamStadusDescription];
}


- (void)updateDashboard{
    self.dashboard.text = [NSString stringWithFormat:@"%@", [UPAVCapturer sharedInstance].dashboard];
    self.dashboard.textColor = [UIColor redColor];
    double delayInSeconds = 1.0;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    __weak UPLiveStreamerLivingVC *weakself = self;
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        [weakself updateDashboard];
    });
}

- (void)dealloc {
    NSLog(@"dealloc %@", self);
}



@end
