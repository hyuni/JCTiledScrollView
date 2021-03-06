//
//  JCTiledScrollView.m
//
//  Copyright (c) 2012-2017 Jesse Collis <jesse@jcmultimedia.com.au>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

#import "JCTiledScrollView.h"
#import "JCTiledView.h"
#import "JCAnnotation.h"
#import "JCAnnotationView.h"
#import "JCVisibleAnnotationTuple.h"
#import "JCAnnotationTapGestureRecognizer.h"
#include <tgmath.h>

#define kStandardUIScrollViewAnimationTime (int64_t)0.10

@interface JCTiledScrollView () <JCTiledBitmapViewDelegate, UIGestureRecognizerDelegate>

@property (nonatomic, strong) UITapGestureRecognizer *singleTapGestureRecognizer;
@property (nonatomic, strong) UITapGestureRecognizer *doubleTapGestureRecognizer;
@property (nonatomic, strong) UITapGestureRecognizer *twoFingerTapGestureRecognizer;
@property (nonatomic, assign) BOOL muteAnnotationUpdates;
@end

@implementation JCTiledScrollView

@synthesize tiledScrollViewDelegate = _tiledScrollViewDelegate;
@synthesize dataSource = _dataSource;

@synthesize levelsOfZoom = _levelsOfZoom;
@synthesize levelsOfDetail = _levelsOfDetail;
@dynamic zoomScale;

@synthesize tiledView = _tiledView;
@synthesize scrollView = _scrollView;
@synthesize canvasView = _canvasView;

@synthesize singleTapGestureRecognizer = _singleTapGestureRecognizer;
@synthesize doubleTapGestureRecognizer = _doubleTapGestureRecognizer;
@synthesize twoFingerTapGestureRecognizer = _twoFingerTapGestureRecognizer;

@synthesize zoomsOutOnTwoFingerTap = _zoomsOutOnTwoFingerTap;
@synthesize zoomsInOnDoubleTap = _zoomsInOnDoubleTap;
@synthesize zoomsToTouchLocation = _zoomsToTouchLocation;
@synthesize centerSingleTap = _centerSingleTap;

@synthesize muteAnnotationUpdates = _muteAnnotationUpdates;

+ (Class)tiledLayerClass
{
  return [JCTiledView class];
}

- (instancetype)initWithFrame:(CGRect)frame contentSize:(CGSize)contentSize
{
	if ((self = [super initWithFrame:frame]))
  {
    self.autoresizingMask = UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth;

    _scrollView = [[UIScrollView alloc] initWithFrame:self.bounds];
    _scrollView.autoresizingMask = UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth;
    _scrollView.delegate = self;
    _scrollView.backgroundColor = [UIColor whiteColor];
    _scrollView.contentSize = contentSize;
    _scrollView.bouncesZoom = YES;
    _scrollView.bounces = YES;
    _scrollView.minimumZoomScale = 1.0;

    self.levelsOfZoom = 2;

    self.zoomsInOnDoubleTap = YES;
    self.zoomsOutOnTwoFingerTap = YES;
    self.centerSingleTap = YES;

    CGRect canvas_frame = CGRectMake(0.0f, 0.0f, _scrollView.contentSize.width, _scrollView.contentSize.height);
    _canvasView = [[UIView alloc] initWithFrame:canvas_frame];
    _canvasView.userInteractionEnabled = NO;

    _tiledView = [[[[self class] tiledLayerClass] alloc] initWithFrame:canvas_frame];
    _tiledView.delegate = self;

    [_scrollView addSubview:self.tiledView];

    [self addSubview:_scrollView];
    [self addSubview:_canvasView];

    _singleTapGestureRecognizer = [[JCAnnotationTapGestureRecognizer alloc] initWithTarget:self action:@selector(singleTapReceived:)];
    _singleTapGestureRecognizer.numberOfTapsRequired = 1;
    _singleTapGestureRecognizer.delegate = self;
    [_tiledView addGestureRecognizer:_singleTapGestureRecognizer];

    _doubleTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTapReceived:)];
    _doubleTapGestureRecognizer.numberOfTapsRequired = 2;
    [_tiledView addGestureRecognizer:_doubleTapGestureRecognizer];

    [_singleTapGestureRecognizer requireGestureRecognizerToFail:_doubleTapGestureRecognizer];

    _twoFingerTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(twoFingerTapReceived:)];
    _twoFingerTapGestureRecognizer.numberOfTouchesRequired = 2;
    _twoFingerTapGestureRecognizer.numberOfTapsRequired = 1;
    [_tiledView addGestureRecognizer:_twoFingerTapGestureRecognizer];
    
    _annotations = [[NSMutableSet alloc] init];
    _visibleAnnotations = [[NSMutableSet alloc] init];
    _recycledAnnotationViews = [[NSMutableSet alloc] init];
    _previousSelectedAnnotationTuple = nil;
      _currentSelectedAnnotationTuple = nil;

    _muteAnnotationUpdates = NO;
	}
	return self;
}


//MARK: UIScrolViewDelegate

- (UIView *)viewForZoomingInScrollView:(__unused UIScrollView *)scrollView
{
  return self.tiledView;
}

- (void)scrollViewDidZoom:(__unused UIScrollView *)scrollView
{
  if ([self.tiledScrollViewDelegate respondsToSelector:@selector(tiledScrollViewDidZoom:)])
  {
    [self.tiledScrollViewDelegate tiledScrollViewDidZoom:self];
  }
}

- (void)scrollViewDidScroll:(__unused UIScrollView *)scrollView
{
  [self correctScreenPositionOfAnnotations];

  if ([self.tiledScrollViewDelegate respondsToSelector:@selector(tiledScrollViewDidScroll:)])
  {
    [self.tiledScrollViewDelegate tiledScrollViewDidScroll:self];
  }
}

//MARK: 

//FIXME: Jesse C - I don't like overloading this here, but the logic is in one place
- (void)setMuteAnnotationUpdates:(BOOL)muteAnnotationUpdates
{
  _muteAnnotationUpdates = muteAnnotationUpdates;
  _scrollView.userInteractionEnabled = !_muteAnnotationUpdates;

  if (!muteAnnotationUpdates)
  {
    [self correctScreenPositionOfAnnotations];
  }
}

//MARK: Gesture Support

- (void)singleTapReceived:(UITapGestureRecognizer *)gestureRecognizer
{
  if ([gestureRecognizer isKindOfClass:[JCAnnotationTapGestureRecognizer class]])
  {
    JCAnnotationTapGestureRecognizer *annotationGestureRecognizer = (JCAnnotationTapGestureRecognizer *) gestureRecognizer;

    _previousSelectedAnnotationTuple = _currentSelectedAnnotationTuple;
    _currentSelectedAnnotationTuple = annotationGestureRecognizer.tapAnnotation;

    if (nil == annotationGestureRecognizer.tapAnnotation)
    {
      if (_previousSelectedAnnotationTuple != nil)
      {
        if ([self.tiledScrollViewDelegate respondsToSelector:@selector(tiledScrollView:didDeselectAnnotationView:)])
        {
          [self.tiledScrollViewDelegate tiledScrollView:self didDeselectAnnotationView:_previousSelectedAnnotationTuple.view];
        }
      }
      else if (self.centerSingleTap)
      {
        [self setContentCenter:[gestureRecognizer locationInView:self.tiledView] animated:YES];
      }

      if ([self.tiledScrollViewDelegate respondsToSelector:@selector(tiledScrollView:didReceiveSingleTap:)])
      {
        [self.tiledScrollViewDelegate tiledScrollView:self didReceiveSingleTap:gestureRecognizer];
      }
    }
    else
    {

      if (_previousSelectedAnnotationTuple != nil)
      {

        JCAnnotationView *oldSelectedAnnotationView = _previousSelectedAnnotationTuple.view;

        if (oldSelectedAnnotationView == nil)
        {
          oldSelectedAnnotationView = [_tiledScrollViewDelegate tiledScrollView:self viewForAnnotation:_previousSelectedAnnotationTuple.annotation];
        }
        if ([self.tiledScrollViewDelegate respondsToSelector:@selector(tiledScrollView:didDeselectAnnotationView:)])
        {
          [self.tiledScrollViewDelegate tiledScrollView:self didDeselectAnnotationView:oldSelectedAnnotationView];
        }
      }

      if (_currentSelectedAnnotationTuple != nil)
      {
        JCAnnotationView *currentSelectedAnnotationView = annotationGestureRecognizer.tapAnnotation.view;
        if ([self.tiledScrollViewDelegate respondsToSelector:@selector(tiledScrollView:didSelectAnnotationView:)])
        {
          [self.tiledScrollViewDelegate tiledScrollView:self didSelectAnnotationView:currentSelectedAnnotationView];

        }
      }
    }
  }
}

- (void)doubleTapReceived:(UITapGestureRecognizer *)gestureRecognizer
{
  if (self.zoomsInOnDoubleTap)
  {
    CGFloat newZoom = (CGFloat) pow(2, (CGFloat) (log2(_scrollView.zoomScale) + (CGFloat) 1.0)); //zoom in one level of detail
    if (newZoom > _scrollView.maximumZoomScale) {
      newZoom = _scrollView.maximumZoomScale;
    }
    
    self.muteAnnotationUpdates = YES;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, kStandardUIScrollViewAnimationTime * NSEC_PER_SEC);
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
      [self setMuteAnnotationUpdates:NO];
    });

    if (self.zoomsToTouchLocation)
    {
      CGRect bounds = _scrollView.bounds;
      CGPoint pointInView = CGPointApplyAffineTransform([gestureRecognizer locationInView:_scrollView], CGAffineTransformMakeScale(1/_scrollView.zoomScale, 1/_scrollView.zoomScale));
      CGSize newSize = CGSizeApplyAffineTransform(bounds.size, CGAffineTransformMakeScale(1 / newZoom, 1 / newZoom));
      [_scrollView zoomToRect:(CGRect){{pointInView.x - (newSize.width / 2), pointInView.y - (newSize.height / 2)}, newSize} animated:YES];
    }
    else
    {
      [_scrollView setZoomScale:newZoom animated:YES];
    }
  }

  if ([self.tiledScrollViewDelegate respondsToSelector:@selector(tiledScrollView:didReceiveDoubleTap:)])
  {
    [self.tiledScrollViewDelegate tiledScrollView:self didReceiveDoubleTap:gestureRecognizer];
  }
}

- (void)twoFingerTapReceived:(UITapGestureRecognizer *)gestureRecognizer
{
  if (self.zoomsOutOnTwoFingerTap)
  {
    CGFloat newZoom = (CGFloat) pow(2, (CGFloat) (log2(_scrollView.zoomScale) - (CGFloat) 1.0)); //zoom out one level of detail
    if (newZoom < _scrollView.minimumZoomScale) {
      newZoom = _scrollView.minimumZoomScale; 
    }
    
    self.muteAnnotationUpdates = YES;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, kStandardUIScrollViewAnimationTime * NSEC_PER_SEC);
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
      [self setMuteAnnotationUpdates:NO];
    });

    [_scrollView setZoomScale:newZoom animated:YES];
  }

  if ([self.tiledScrollViewDelegate respondsToSelector:@selector(tiledScrollView:didReceiveTwoFingerTap:)])
  {
    [self.tiledScrollViewDelegate tiledScrollView:self didReceiveTwoFingerTap:gestureRecognizer];
  }
}

- (CGPoint)screenPositionForAnnotation:(id<JCAnnotation>)annotation
{
  CGPoint position;
  position.x = (annotation.contentPosition.x * self.zoomScale) - _scrollView.contentOffset.x;
  position.y = (annotation.contentPosition.y * self.zoomScale) - _scrollView.contentOffset.y;
  return position;
}

- (void)correctScreenPositionOfAnnotations
{
  [CATransaction begin];
  [CATransaction setAnimationDuration:0.0];

  if ((_scrollView.isZoomBouncing || _muteAnnotationUpdates) && !_scrollView.isZooming)
  {
    for (JCVisibleAnnotationTuple *t in _visibleAnnotations)
    {
      t.view.position = [self screenPositionForAnnotation:t.annotation];
    }
  }
  else
  {
    for (id <JCAnnotation> annotation in _annotations)
    {
      [CATransaction begin];

      CGPoint screenPosition = [self screenPositionForAnnotation:annotation];
      JCVisibleAnnotationTuple *t = [_visibleAnnotations visibleAnnotationTupleForAnnotation:annotation];

      if ([self point:screenPosition isWithinBounds:self.bounds])
      {
        if (nil == t)
        {
          JCAnnotationView *view = [_tiledScrollViewDelegate tiledScrollView:self viewForAnnotation:annotation];
          if (nil == view) continue;
          view.position = screenPosition;

          t = [JCVisibleAnnotationTuple instanceWithAnnotation:annotation view:view];
          if ([self.tiledScrollViewDelegate respondsToSelector:@selector(tiledScrollView:annotationWillAppear:)])
          {
            [self.tiledScrollViewDelegate tiledScrollView:self annotationWillAppear:t.annotation];
          }

          [_visibleAnnotations addObject:t];
          [_canvasView addSubview:t.view];

          [CATransaction begin];
          [CATransaction setValue:(id) kCFBooleanTrue forKey:kCATransactionDisableActions];
          CABasicAnimation *theAnimation = [CABasicAnimation animationWithKeyPath:@"opacity"];
          theAnimation.duration = 0.3;
          theAnimation.repeatCount = 1;
          theAnimation.fromValue = [NSNumber numberWithFloat:0.0];
          theAnimation.toValue = [NSNumber numberWithFloat:1.0];
          [t.view.layer addAnimation:theAnimation forKey:@"animateOpacity"];
          [CATransaction commit];
          if ([self.tiledScrollViewDelegate respondsToSelector:@selector(tiledScrollView:annotationDidAppear:)])
          {
            [self.tiledScrollViewDelegate tiledScrollView:self annotationDidAppear:t.annotation];
          }
        }
        else
        {
          if (t == _currentSelectedAnnotationTuple)
          {
            [_canvasView addSubview:t.view];
          }
          t.view.position = screenPosition;
        }
      }
      else
      {
        if (nil != t)
        {
          if ([self.tiledScrollViewDelegate respondsToSelector:@selector(tiledScrollView:annotationWillDisappear:)])
          {
            [self.tiledScrollViewDelegate tiledScrollView:self annotationWillAppear:t.annotation];
          }

          if (t != _currentSelectedAnnotationTuple)
          {
            [t.view removeFromSuperview];
            [_recycledAnnotationViews addObject:t.view];
            [_visibleAnnotations removeObject:t];
          }
          else
          {
          //FIXME: Anthony D - I don't like let the view in visible annotations array, but the logic is in one place
            [t.view removeFromSuperview];
          }

          if ([self.tiledScrollViewDelegate respondsToSelector:@selector(tiledScrollView:annotationDidDisappear:)])
          {
            [self.tiledScrollViewDelegate tiledScrollView:self annotationDidDisappear:t.annotation];
          }
        }
      }
      [CATransaction commit];
    }
  }
  [CATransaction commit];
}


//MARK: UIGestureRecognizerDelegate
//Catch our own tap gesture if it is on an annotation view to set annotation
//Return NO to only recognize single tap on annotation
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
  CGPoint location = [gestureRecognizer locationInView:self.canvasView];

  if ([gestureRecognizer isKindOfClass:[JCAnnotationTapGestureRecognizer class]])
  {
    [(JCAnnotationTapGestureRecognizer *) gestureRecognizer setTapAnnotation:nil];
  }

  for (JCVisibleAnnotationTuple *t in _visibleAnnotations)
  {
    if (CGRectContainsPoint(t.view.frame, location))
    {
      if ([gestureRecognizer isKindOfClass:[JCAnnotationTapGestureRecognizer class]])
      {
        [(JCAnnotationTapGestureRecognizer *) gestureRecognizer setTapAnnotation:t];
      }
      return YES;
    }
  }

  //Deal with all tap gesture
  return YES;
}


//MARK: JCTiledScrollView

- (CGFloat)zoomScale
{
  return _scrollView.zoomScale;
}

- (void)setZoomScale:(CGFloat)zoomScale
{
  [self setZoomScale:zoomScale animated:NO];
}

- (void)setZoomScale:(CGFloat)zoomScale animated:(BOOL)animated
{
  [_scrollView setZoomScale:zoomScale animated:animated];
}

- (void)setLevelsOfZoom:(size_t)levelsOfZoom
{
  _levelsOfZoom = levelsOfZoom;
  _scrollView.maximumZoomScale = (float)powf(2.0f, MAX(0.0f, levelsOfZoom));
}

- (void)setLevelsOfDetail:(size_t)levelsOfDetail
{
  if (levelsOfDetail == 1) NSLog(@"Note: Setting levelsOfDetail to 1 causes strange behaviour");

  _levelsOfDetail = levelsOfDetail;
  [self.tiledView setNumberOfZoomLevels:levelsOfDetail];
}

- (void)setContentCenter:(CGPoint)center animated:(BOOL)animated
{
  CGPoint new_contentOffset = _scrollView.contentOffset;
  
  if (_scrollView.contentSize.width > _scrollView.bounds.size.width)
  {
    new_contentOffset.x = MAX(0.0f, (center.x * _scrollView.zoomScale) - (_scrollView.bounds.size.width / 2.0f));
    new_contentOffset.x = MIN(new_contentOffset.x, (_scrollView.contentSize.width - _scrollView.bounds.size.width));
  }

  if (_scrollView.contentSize.height > _scrollView.bounds.size.height)
  {
    new_contentOffset.y = MAX(0.0f, (center.y * _scrollView.zoomScale) - (_scrollView.bounds.size.height / 2.0f));
    new_contentOffset.y = MIN(new_contentOffset.y, (_scrollView.contentSize.height - _scrollView.bounds.size.height));
  }
  [_scrollView setContentOffset:new_contentOffset animated:animated];
}

//MARK: JCTileSource

- (UIImage *)tiledView:(__unused JCTiledView *)tiledView imageForRow:(NSInteger)row column:(NSInteger)column scale:(NSInteger)scale
{
  return [self.dataSource tiledScrollView:self imageForRow:row column:column scale:scale];
}

//MARK: Annotation Recycling

- (JCAnnotationView *)dequeueReusableAnnotationViewWithReuseIdentifier:(NSString *)reuseIdentifier
{
  id view = nil;

  for (JCAnnotationView *obj in _recycledAnnotationViews)
  {
    if ([[obj reuseIdentifier] isEqualToString:reuseIdentifier])
    {
      view = obj;
      break;
    }
  }
  
  if (nil != view)
  {
    [_recycledAnnotationViews removeObject:view];
    return view;
  }
  return nil;
}

//MARK: Annotations

- (BOOL)point:(CGPoint)point isWithinBounds:(CGRect)bounds
{
  return CGRectContainsPoint(CGRectInset(bounds, -25.,-25.), point);
}

- (void)refreshAnnotations
{
  [self correctScreenPositionOfAnnotations];
}

- (void)addAnnotation:(id<JCAnnotation>)annotation
{
  [_annotations addObject:annotation];

  CGPoint screenPosition = [self screenPositionForAnnotation:annotation];

  if ([self point:screenPosition isWithinBounds:self.bounds])
  {
    JCAnnotationView *view = [_tiledScrollViewDelegate tiledScrollView:self viewForAnnotation:annotation];
    view.position = screenPosition;

    JCVisibleAnnotationTuple *t = [JCVisibleAnnotationTuple instanceWithAnnotation:annotation view:view];
    [_visibleAnnotations addObject:t];

    [_canvasView addSubview:view];
  }
}

- (void)addAnnotations:(NSArray *)annotations
{
  for (id annotation in annotations)
  {
    [self addAnnotation:annotation];
  }
}

- (void)removeAnnotation:(id<JCAnnotation>)annotation
{
  if ([_annotations containsObject:annotation])
  {
    JCVisibleAnnotationTuple *t = [_visibleAnnotations visibleAnnotationTupleForAnnotation:annotation];
    if (t)
    {
      [t.view removeFromSuperview];
      [_visibleAnnotations removeObject:t];
    }

    [_annotations removeObject:annotation];
  }
}

- (void)removeAnnotations:(NSArray *)annotations
{
  for (id annotation in annotations)
  {
    [self removeAnnotation:annotation];
  }
}

- (void)removeAllAnnotations
{
  [self removeAnnotations:[_annotations allObjects]];
}

@end
