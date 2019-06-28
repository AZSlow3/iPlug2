/*
 ==============================================================================

 This file is part of the iPlug 2 library. Copyright (C) the iPlug 2 developers.

 See LICENSE.txt for  more info.

 ==============================================================================
*/

#import <QuartzCore/QuartzCore.h>
#ifdef IGRAPHICS_IMGUI
#import <Metal/Metal.h>
#include "imgui.h"
#import "imgui_impl_metal.h"
#endif

#import "IGraphicsIOS_view.h"
#include "IControl.h"
#include "IPlugParameter.h"

@implementation IGraphicsIOS_View

- (id) initWithIGraphics: (IGraphicsIOS*) pGraphics
{
  TRACE;

  mGraphics = pGraphics;
  CGRect r = CGRectMake(0.f, 0.f, (float) pGraphics->WindowWidth(), (float) pGraphics->WindowHeight());
  self = [super initWithFrame:r];

  self.layer.opaque = YES;
  self.layer.contentsScale = [UIScreen mainScreen].scale;
  
  self.multipleTouchEnabled = NO;
  
  return self;
}

- (void)setFrame:(CGRect)frame
{
  [super setFrame:frame];
  
  // During the first layout pass, we will not be in a view hierarchy, so we guess our scale
  CGFloat scale = [UIScreen mainScreen].scale;
  
  // If we've moved to a window by the time our frame is being set, we can take its scale as our own
  if (self.window)
    scale = self.window.screen.scale;
  
  CGSize drawableSize = self.bounds.size;
  
  // Since drawable size is in pixels, we need to multiply by the scale to move from points to pixels
  drawableSize.width *= scale;
  drawableSize.height *= scale;
  
  self.metalLayer.drawableSize = drawableSize;
}

- (void) onTouchEvent:(ETouchEvent)eventType withTouches:(NSSet*)touches withEvent:(UIEvent*)event
{
  if(mGraphics == nullptr) //TODO: why?
    return;
  
  NSEnumerator* pEnumerator = [[event allTouches] objectEnumerator];
  UITouch* pTouch;
  
  std::vector<IMouseInfo> points;

  while ((pTouch = [pEnumerator nextObject]))
  {
    CGPoint pos = [pTouch locationInView:pTouch.view];
    
    IMouseInfo point;
    
    auto ds = mGraphics->GetDrawScale();
    
    point.ms.L = true;
    point.ms.idx = reinterpret_cast<uintptr_t>(pTouch);
    point.ms.radius = [pTouch majorRadius];
  
    point.x = pos.x / ds;
    point.y = pos.y / ds;
    CGPoint posPrev = [pTouch previousLocationInView: self];
    point.dX = (pos.x - posPrev.x) / ds;
    point.dY = (pos.y - posPrev.y) / ds;
    
    if([touches containsObject:pTouch])
      points.push_back(point);
  }

//  DBGMSG("%lu\n", points[0].ms.idx);
  
  if(eventType == ETouchEvent::Began)
    mGraphics->OnMouseDown(points);
  
  if(eventType == ETouchEvent::Moved)
    mGraphics->OnMouseDrag(points);
  
  if(eventType == ETouchEvent::Ended)
    mGraphics->OnMouseUp(points);
  
  if(eventType == ETouchEvent::Cancelled)
    mGraphics->OnTouchCancelled(points);
}

- (void) touchesBegan:(NSSet*)touches withEvent:(UIEvent*)event
{
  [self onTouchEvent:ETouchEvent::Began withTouches:touches withEvent:event];
}

- (void) touchesMoved:(NSSet*)touches withEvent:(UIEvent*)event
{
  [self onTouchEvent:ETouchEvent::Moved withTouches:touches withEvent:event];
}

- (void) touchesEnded:(NSSet*)touches withEvent:(UIEvent*)event
{
  [self onTouchEvent:ETouchEvent::Ended withTouches:touches withEvent:event];
}

- (void) touchesCancelled:(NSSet*)touches withEvent:(UIEvent*)event
{
  [self onTouchEvent:ETouchEvent::Cancelled withTouches:touches withEvent:event];
}

- (CAMetalLayer*) metalLayer
{
  return (CAMetalLayer *)self.layer;
}

- (void)dealloc
{
  [_displayLink invalidate];
  
  [super dealloc];
}

- (void)didMoveToSuperview
{
  [super didMoveToSuperview];
  if (self.superview)
  {
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(redraw:)];
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
  }
  else
  {
    [self.displayLink invalidate];
    self.displayLink = nil;
  }
}

- (void)redraw:(CADisplayLink*) displayLink
{
  IRECTList rects;
  
  if(mGraphics)
  {
    if (mGraphics->IsDirty(rects))
    {
      mGraphics->SetAllControlsClean();
      mGraphics->Draw(rects);
    }
  }
}

- (BOOL) isOpaque
{
  return YES;
}

- (BOOL) acceptsFirstResponder
{
  return YES;
}

- (BOOL)canBecomeFirstResponder
{
  return YES;
}

- (void) removeFromSuperview
{
  [self.displayLink invalidate];
  self.displayLink = nil;
}

- (void) controlTextDidEndEditing: (NSNotification*) aNotification
{
}

- (IPopupMenu*) createPopupMenu: (const IPopupMenu&) menu : (CGRect) bounds;
{
  return nullptr;
}

- (void) createTextEntry: (int) paramIdx : (const IText&) text : (const char*) str : (int) length : (CGRect) areaRect
{
  NSString* titleNString = [NSString stringWithUTF8String:"Please input a value"];
  NSString* captionNString = [NSString stringWithUTF8String:""];
  
  UIAlertController* alertController = [UIAlertController alertControllerWithTitle:titleNString
                                                                 message:captionNString
                                                          preferredStyle:UIAlertControllerStyleAlert];
  
  [alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
    textField.placeholder = [NSString stringWithUTF8String:str];
    textField.textColor = [UIColor blueColor];
    textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    textField.borderStyle = UITextBorderStyleRoundedRect;
  }];
  
  void (^handlerBlock)(UIAlertAction*) =
  ^(UIAlertAction* action) {
    
    NSString* result = alertController.textFields[0].text;

    char* txt = (char*)[result UTF8String];
    
    mGraphics->SetControlValueAfterTextEdit(txt);
    mGraphics->SetAllControlsDirty();
    
  };
  
  UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:handlerBlock];
  [alertController addAction:okAction];
  UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:handlerBlock];
  [alertController addAction:cancelAction];
  
  [self.window.rootViewController presentViewController:alertController animated:YES completion:nil]; // TODO: linked to plugin view (e.g. can be covered by keyboard)
}

- (void) endUserInput
{
}

- (void) showMessageBox: (const char*) str : (const char*) caption : (EMsgBoxType) type : (IMsgBoxCompletionHanderFunc) completionHandler
{
  NSString* titleNString = [NSString stringWithUTF8String:str];
  NSString* captionNString = [NSString stringWithUTF8String:caption];
  
  UIAlertController* alertController = [UIAlertController alertControllerWithTitle:titleNString
                                                                 message:captionNString
                                                          preferredStyle:UIAlertControllerStyleAlert];
  
  void (^handlerBlock)(UIAlertAction*) =
  ^(UIAlertAction* action) {
    
    if(completionHandler != nullptr)
    {
      EMsgBoxResult result = EMsgBoxResult::kCANCEL;
      
      if([action.title isEqualToString:@"OK"])
        result = EMsgBoxResult::kOK;
      if([action.title isEqualToString:@"Cancel"])
        result = EMsgBoxResult::kCANCEL;
      if([action.title isEqualToString:@"Yes"])
        result = EMsgBoxResult::kYES;
      if([action.title isEqualToString:@"No"])
        result = EMsgBoxResult::kNO;
      if([action.title isEqualToString:@"Retry"])
        result = EMsgBoxResult::kRETRY;
      
      completionHandler(result);
    }
    
  };
  
  if(type == kMB_OK || type == kMB_OKCANCEL)
  {
    UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:handlerBlock];
    [alertController addAction:okAction];
  }
  
  if(type == kMB_YESNO || type == kMB_YESNOCANCEL)
  {
    UIAlertAction* yesAction = [UIAlertAction actionWithTitle:@"Yes" style:UIAlertActionStyleDefault handler:handlerBlock];
    [alertController addAction:yesAction];
    
    UIAlertAction* noAction = [UIAlertAction actionWithTitle:@"No" style:UIAlertActionStyleDefault handler:handlerBlock];
    [alertController addAction:noAction];
  }
  
  if(type == kMB_RETRYCANCEL)
  {
    UIAlertAction* retryAction = [UIAlertAction actionWithTitle:@"Retry" style:UIAlertActionStyleDefault handler:handlerBlock];
    [alertController addAction:retryAction];
  }
  
  if(type == kMB_OKCANCEL || type == kMB_YESNOCANCEL || type == kMB_RETRYCANCEL)
  {
    UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:handlerBlock];
    [alertController addAction:cancelAction];
  }
  
  [self.window.rootViewController presentViewController:alertController animated:YES completion:nil];
}

- (void) attachGestureRecognizer: (EGestureType) type
{
  UIGestureRecognizer* gestureRecognizer;
  
  switch (type)
  {
    case EGestureType::DoubleTap:
    case EGestureType::TripleTap:
    {
      gestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onTapGesture:)];
      [(UITapGestureRecognizer*) gestureRecognizer setNumberOfTapsRequired: type == EGestureType::DoubleTap ? 2 : 3];
      [(UITapGestureRecognizer*) gestureRecognizer setNumberOfTouchesRequired:1];
      break;
    }
    case EGestureType::LongPress1:
    case EGestureType::LongPress2:
    {
      gestureRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(onLongPressGesture:)];
      [(UILongPressGestureRecognizer*) gestureRecognizer setNumberOfTouchesRequired: type == EGestureType::LongPress1 ? 1 : 2];
      break;
    }
    case EGestureType::SwipeLeft:
    {
      gestureRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(onSwipeGesture:)];
      [(UISwipeGestureRecognizer*) gestureRecognizer setDirection:UISwipeGestureRecognizerDirectionLeft];
      break;
    }
    case EGestureType::SwipeRight:
    {
      gestureRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(onSwipeGesture:)];
      [(UISwipeGestureRecognizer*) gestureRecognizer setDirection:UISwipeGestureRecognizerDirectionRight];
      break;
    }
    case EGestureType::SwipeUp:
    {
      gestureRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(onSwipeGesture:)];
      [(UISwipeGestureRecognizer*) gestureRecognizer setDirection:UISwipeGestureRecognizerDirectionUp];
      break;
    }
    case EGestureType::SwipeDown:
    {
      gestureRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(onSwipeGesture:)];
      [(UISwipeGestureRecognizer*) gestureRecognizer setDirection:UISwipeGestureRecognizerDirectionDown];
      break;
    }
    case EGestureType::Pinch:
    {
      gestureRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(onPinchGesture:)];
      break;
    }
    case EGestureType::Rotate:
    {
      gestureRecognizer = [[UIRotationGestureRecognizer alloc] initWithTarget:self action:@selector(onRotateGesture:)];
      break;
    }
    default:
      return;
  }
    
  gestureRecognizer.delegate = self;
  gestureRecognizer.cancelsTouchesInView = YES;
  gestureRecognizer.delaysTouchesBegan = YES;
  [self addGestureRecognizer:gestureRecognizer];
  [gestureRecognizer release];
}

- (void) onTapGesture: (UITapGestureRecognizer *) recognizer
{
  CGPoint p = [recognizer locationInView:self];
  auto ds = mGraphics->GetDrawScale();
  IGestureInfo info;
  info.x = p.x / ds;
  info.y = p.y / ds;
  info.type = recognizer.numberOfTapsRequired == 2 ? EGestureType::DoubleTap : EGestureType::TripleTap;
  
  mGraphics->OnGestureRecognized(info);
}

- (void) onLongPressGesture: (UILongPressGestureRecognizer*) recognizer
{
  CGPoint p = [recognizer locationInView:self];
  auto ds = mGraphics->GetDrawScale();
  IGestureInfo info;
  info.x = p.x / ds;
  info.y = p.y / ds;
  if(recognizer.state == UIGestureRecognizerStateBegan)
    info.state = EGestureState::Began;
  else if(recognizer.state == UIGestureRecognizerStateChanged)
    info.state = EGestureState::InProcess;
  else if(recognizer.state == UIGestureRecognizerStateEnded)
    info.state = EGestureState::Ended;
  
  info.type = recognizer.numberOfTouchesRequired == 1 ? EGestureType::LongPress1 : EGestureType::LongPress2;
  
  mGraphics->OnGestureRecognized(info);
}

- (void) onSwipeGesture: (UISwipeGestureRecognizer*) recognizer
{
  CGPoint p = [recognizer locationInView:self];
  auto ds = mGraphics->GetDrawScale();
  IGestureInfo info;
  info.x = p.x / ds;
  info.y = p.y / ds;

  switch (recognizer.direction) {
    case UISwipeGestureRecognizerDirectionLeft: info.type = EGestureType::SwipeLeft; break;
    case UISwipeGestureRecognizerDirectionRight: info.type = EGestureType::SwipeRight; break;
    case UISwipeGestureRecognizerDirectionUp: info.type = EGestureType::SwipeUp; break;
    case UISwipeGestureRecognizerDirectionDown: info.type = EGestureType::SwipeDown; break;
    default:
      break;
  }
  
  mGraphics->OnGestureRecognized(info);
}

- (void) onPinchGesture: (UIPinchGestureRecognizer*) recognizer
{
  CGPoint p = [recognizer locationInView:self];
  auto ds = mGraphics->GetDrawScale();
  IGestureInfo info;
  info.x = p.x / ds;
  info.y = p.y / ds;
  info.velocity = recognizer.velocity;
  info.scale = recognizer.scale;
  
  if(recognizer.state == UIGestureRecognizerStateBegan)
    info.state = EGestureState::Began;
  else if(recognizer.state == UIGestureRecognizerStateChanged)
    info.state = EGestureState::InProcess;
  else if(recognizer.state == UIGestureRecognizerStateEnded)
    info.state = EGestureState::Ended;
  
  info.type = EGestureType::Pinch;
  
  mGraphics->OnGestureRecognized(info);
}

- (void) onRotateGesture: (UIRotationGestureRecognizer*) recognizer
{
  CGPoint p = [recognizer locationInView:self];
  auto ds = mGraphics->GetDrawScale();
  IGestureInfo info;
  info.x = p.x / ds;
  info.y = p.y / ds;
  info.velocity = recognizer.velocity;
  info.angle = RadToDeg(recognizer.rotation);
  
  if(recognizer.state == UIGestureRecognizerStateBegan)
    info.state = EGestureState::Began;
  else if(recognizer.state == UIGestureRecognizerStateChanged)
    info.state = EGestureState::InProcess;
  else if(recognizer.state == UIGestureRecognizerStateEnded)
    info.state = EGestureState::Ended;
  
  info.type = EGestureType::Rotate;

  mGraphics->OnGestureRecognized(info);
}

-(BOOL) gestureRecognizer:(UIGestureRecognizer*) gestureRecognizer shouldReceiveTouch:(UITouch*)touch
{
  CGPoint pos = [touch locationInView:touch.view];
  
  auto ds = mGraphics->GetDrawScale();

  if(mGraphics->RespondsToGesture(pos.x / ds, pos.y / ds))
    return TRUE;
  else
    return FALSE;
}

+ (Class)layerClass
{
  return [CAMetalLayer class];
}

@end

#ifdef IGRAPHICS_IMGUI

@implementation IGRAPHICS_IMGUIVIEW
{
}

- (id) initWithIGraphicsView: (IGraphicsIOS_View*) pView;
{
  mView = pView;
  self = [super initWithFrame:[pView frame] device: MTLCreateSystemDefaultDevice()];
  if(self) {
    _commandQueue = [self.device newCommandQueue];
    self.layer.opaque = NO;
  }
  
  return self;
}

- (void)drawRect:(CGRect)rect
{
  id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
  
  MTLRenderPassDescriptor *renderPassDescriptor = self.currentRenderPassDescriptor;
  if (renderPassDescriptor != nil)
  {
    renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0,0,0,0);
    
    id <MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    [renderEncoder pushDebugGroup:@"ImGui IGraphics"];
    
    ImGui_ImplMetal_NewFrame(renderPassDescriptor);
    
    mView->mGraphics->mImGuiRenderer->DoFrame();
    
    ImDrawData *drawData = ImGui::GetDrawData();
    ImGui_ImplMetal_RenderDrawData(drawData, commandBuffer, renderEncoder);
    
    [renderEncoder popDebugGroup];
    [renderEncoder endEncoding];
    
    [commandBuffer presentDrawable:self.currentDrawable];
  }
  [commandBuffer commit];
}

@end

#endif
