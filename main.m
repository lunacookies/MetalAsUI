@import AppKit;
@import Metal;
@import QuartzCore;
@import simd;

static const uint32_t RowCount = 10;
static const uint32_t ColumnCount = 10;
static const float Diameter = 50;
static const float Padding = 10;
static const NSInteger MeasurementWindowSize = 10;

@interface MetalView : NSView
@end

@implementation MetalView
{
	CADisplayLink *displayLink;
	id<MTLDevice> device;
	id<MTLCommandQueue> commandQueue;
	id<MTLRenderPipelineState> pipelineState;

	IOSurfaceRef surface;
	id<MTLTexture> texture;

	simd_float2 positionNudge;

	CFTimeInterval previousFrameStart;
	CFTimeInterval recentMeasurements[MeasurementWindowSize];
	NSUInteger oldestMeasurementIndex;
}

- (instancetype)initWithFrame:(NSRect)frame
{
	self = [super initWithFrame:frame];
	self.wantsLayer = YES;
	self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawDuringViewResize;

	device = MTLCreateSystemDefaultDevice();
	commandQueue = [device newCommandQueue];

	id<MTLLibrary> library = [device newDefaultLibrary];

	MTLRenderPipelineDescriptor *descriptor = [[MTLRenderPipelineDescriptor alloc] init];
	descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
	descriptor.vertexFunction = [library newFunctionWithName:@"vertex_main"];
	descriptor.fragmentFunction = [library newFunctionWithName:@"fragment_main"];
	descriptor.colorAttachments[0].blendingEnabled = YES;
	descriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
	descriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
	descriptor.colorAttachments[0].destinationRGBBlendFactor =
	        MTLBlendFactorOneMinusSourceAlpha;
	descriptor.colorAttachments[0].destinationAlphaBlendFactor =
	        MTLBlendFactorOneMinusSourceAlpha;
	pipelineState = [device newRenderPipelineStateWithDescriptor:descriptor error:nil];

	displayLink = [self displayLinkWithTarget:self selector:@selector(displayLinkDidFire)];
	// [displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];

	return self;
}

- (BOOL)wantsUpdateLayer
{
	return YES;
}

- (void)displayLinkDidFire
{
	// positionNudge.x = (float)cos(CACurrentMediaTime() * 2);
	// positionNudge.y = (float)sin(CACurrentMediaTime() * 2);
	self.needsDisplay = YES;
}

- (void)updateLayer
{
	CFTimeInterval currentFrameStart = CACurrentMediaTime();
	CFTimeInterval frameDuration = currentFrameStart - previousFrameStart;
	printf("%.f  %8.2f ", 1 / frameDuration, frameDuration * 1000);
	if (frameDuration * 1000 > 9)
	{
		printf("***  ");
	}
	else
	{
		printf("___  ");
	}
	previousFrameStart = currentFrameStart;
	recentMeasurements[oldestMeasurementIndex] = frameDuration;
	oldestMeasurementIndex = (oldestMeasurementIndex + 1) % MeasurementWindowSize;

	NSColorSpace *colorSpace = self.window.colorSpace;
	NSColor *fillColor = [NSColor.textBackgroundColor colorUsingColorSpace:colorSpace];
	NSColor *backgroundColor = [NSColor.systemPurpleColor colorUsingColorSpace:colorSpace];

	// id<CAMetalDrawable> drawable = [metalLayer nextDrawable];

	id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];

	MTLRenderPassDescriptor *descriptor = [MTLRenderPassDescriptor renderPassDescriptor];
	descriptor.colorAttachments[0].texture = texture;
	descriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
	descriptor.colorAttachments[0].clearColor =
	        MTLClearColorMake(backgroundColor.redComponent, backgroundColor.greenComponent,
	                backgroundColor.blueComponent, backgroundColor.alphaComponent);

	id<MTLRenderCommandEncoder> encoder =
	        [commandBuffer renderCommandEncoderWithDescriptor:descriptor];

	[encoder setRenderPipelineState:pipelineState];

	simd_float2 resolution = 0;
	resolution.x = texture.width;
	resolution.y = texture.height;
	[encoder setVertexBytes:&resolution length:sizeof(resolution) atIndex:1];

	[encoder setVertexBytes:&ColumnCount length:sizeof(ColumnCount) atIndex:2];

	float scaleFactor = (float)self.window.backingScaleFactor;
	float diameter = Diameter * scaleFactor;
	float padding = Padding * scaleFactor;
	[encoder setVertexBytes:&diameter length:sizeof(diameter) atIndex:3];
	[encoder setVertexBytes:&padding length:sizeof(padding) atIndex:4];
	[encoder setFragmentBytes:&diameter length:sizeof(diameter) atIndex:0];

	simd_float4 color = 0;
	color.r = (float)fillColor.redComponent;
	color.g = (float)fillColor.greenComponent;
	color.b = (float)fillColor.blueComponent;
	color.a = (float)fillColor.alphaComponent;
	[encoder setFragmentBytes:&color length:sizeof(color) atIndex:1];

	simd_float2 gridDimensions = 0;
	gridDimensions.x = ColumnCount;
	gridDimensions.y = RowCount;
	simd_float2 totalSize = 0;
	totalSize += Diameter * gridDimensions;
	totalSize += Padding * (gridDimensions - 1);
	totalSize *= (float)self.window.backingScaleFactor;

	[self drawQuadrantWithEncoder:encoder atOffset:0];

	[self drawQuadrantWithEncoder:encoder
	                     atOffset:simd_make_float2(0, resolution.y - totalSize.y)];

	[self drawQuadrantWithEncoder:encoder
	                     atOffset:simd_make_float2(resolution.x - totalSize.x, 0)];

	[self drawQuadrantWithEncoder:encoder atOffset:resolution - totalSize];

	[encoder endEncoding];

	[commandBuffer commit];
	[commandBuffer waitUntilCompleted];

	// Needed to force an update, for some reason.
	self.layer.contents = nil;
	self.layer.contents = (__bridge id)surface;

	CFTimeInterval sum = 0;
	CFTimeInterval minimum = INFINITY;
	CFTimeInterval maximum = -1;
	for (NSInteger i = 0; i < MeasurementWindowSize; i++)
	{
		CFTimeInterval measurement = recentMeasurements[i];
		sum += measurement;

		if (measurement < minimum)
		{
			minimum = measurement;
		}

		if (measurement > maximum)
		{
			maximum = measurement;
		}
	}
	CFTimeInterval average = sum / MeasurementWindowSize;
	printf("[avg %6.2f] [min %6.2f] [max %6.2f]\n", average * 1000, minimum * 1000,
	        maximum * 1000);
}

- (void)drawQuadrantWithEncoder:(id<MTLRenderCommandEncoder>)encoder atOffset:(simd_float2)offset
{
	offset += positionNudge;

	[encoder setVertexBytes:&offset length:sizeof(offset) atIndex:0];

	[encoder drawPrimitives:MTLPrimitiveTypeTriangle
	            vertexStart:0
	            vertexCount:6
	          instanceCount:RowCount * ColumnCount];
}

- (void)viewDidChangeBackingProperties
{
	[super viewDidChangeBackingProperties];
	[self updateFramebuffer];
}

- (void)setFrameSize:(NSSize)size
{
	[super setFrameSize:size];
	[self updateFramebuffer];
}

- (void)updateFramebuffer
{
	NSSize size = [self convertSizeToBacking:self.frame.size];

	NSDictionary *properties = @{
		(__bridge NSString *)kIOSurfaceWidth : @(size.width),
		(__bridge NSString *)kIOSurfaceHeight : @(size.height),
		(__bridge NSString *)kIOSurfaceBytesPerElement : @4,
		(__bridge NSString *)kIOSurfacePixelFormat : @(kCVPixelFormatType_32BGRA),
	};

	MTLTextureDescriptor *descriptor = [[MTLTextureDescriptor alloc] init];
	descriptor.width = (NSUInteger)size.width;
	descriptor.height = (NSUInteger)size.height;
	descriptor.usage = MTLTextureUsageRenderTarget;
	descriptor.pixelFormat = MTLPixelFormatBGRA8Unorm;

	if (surface != NULL)
	{
		CFRelease(surface);
	}

	surface = IOSurfaceCreate((__bridge CFDictionaryRef)properties);
	texture = [device newTextureWithDescriptor:descriptor iosurface:surface plane:0];
}

@end

@interface CGView : NSView
@end

@implementation CGView
{
	CADisplayLink *displayLink;
	simd_float2 positionNudge;
	CFTimeInterval previousFrameStart;
	CFTimeInterval recentMeasurements[MeasurementWindowSize];
	NSUInteger oldestMeasurementIndex;
}

- (instancetype)initWithFrame:(NSRect)frame
{
	self = [super initWithFrame:frame];
	displayLink = [self displayLinkWithTarget:self selector:@selector(displayLinkDidFire)];
	// [displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
	return self;
}

- (void)displayLinkDidFire
{
	// positionNudge.x = (float)cos(CACurrentMediaTime() * 2);
	// positionNudge.y = (float)sin(CACurrentMediaTime() * 2);
	self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)dirtyRect
{
	CFTimeInterval currentFrameStart = CACurrentMediaTime();
	CFTimeInterval frameDuration = currentFrameStart - previousFrameStart;
	printf("%.f  %8.2f ", 1 / frameDuration, frameDuration * 1000);
	if (frameDuration * 1000 > 9)
	{
		printf("***  ");
	}
	else
	{
		printf("___  ");
	}
	previousFrameStart = currentFrameStart;
	recentMeasurements[oldestMeasurementIndex] = frameDuration;
	oldestMeasurementIndex = (oldestMeasurementIndex + 1) % MeasurementWindowSize;

	[super drawRect:dirtyRect];

	[NSColor.systemPurpleColor setFill];
	NSRectFill(self.bounds);

	simd_float2 size = 0;
	size.x = (float)self.frame.size.width;
	size.y = (float)self.frame.size.height;

	simd_float2 gridDimensions = 0;
	gridDimensions.x = ColumnCount;
	gridDimensions.y = RowCount;
	simd_float2 totalSize = 0;
	totalSize += Diameter * gridDimensions;
	totalSize += Padding * (gridDimensions - 1);

	[NSColor.textBackgroundColor setFill];

	[self drawQuadrantAtOffset:simd_make_float2(0, 0)];
	[self drawQuadrantAtOffset:simd_make_float2(size.x - totalSize.x, 0)];
	[self drawQuadrantAtOffset:simd_make_float2(0, size.y - totalSize.y)];
	[self drawQuadrantAtOffset:size - totalSize];

	CFTimeInterval sum = 0;
	CFTimeInterval minimum = INFINITY;
	CFTimeInterval maximum = -1;
	for (NSInteger i = 0; i < MeasurementWindowSize; i++)
	{
		CFTimeInterval measurement = recentMeasurements[i];
		sum += measurement;

		if (measurement < minimum)
		{
			minimum = measurement;
		}

		if (measurement > maximum)
		{
			maximum = measurement;
		}
	}
	CFTimeInterval average = sum / MeasurementWindowSize;
	printf("[avg %6.2f] [min %6.2f] [max %6.2f]\n", average * 1000, minimum * 1000,
	        maximum * 1000);
}

- (void)drawQuadrantAtOffset:(simd_float2)offset
{
	float scaleFactor = (float)self.window.backingScaleFactor;

	for (uint32_t x = 0; x < ColumnCount; x++)
	{
		for (uint32_t y = 0; y < RowCount; y++)
		{
			simd_uint2 location = simd_make_uint2(x, y);
			simd_float2 position = offset + positionNudge / scaleFactor +
			                       simd_float(location) * (Diameter + Padding);

			NSRect circleRect = {0};
			circleRect.origin.x = position.x;
			circleRect.origin.y = position.y;
			circleRect.size.width = Diameter;
			circleRect.size.height = Diameter;

			NSBezierPath *circlePath =
			        [NSBezierPath bezierPathWithOvalInRect:circleRect];
			[circlePath fill];
		}
	}
}

@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation AppDelegate
{
	NSWindow *window;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
	window = [[NSWindow alloc]
	        initWithContentRect:NSMakeRect(100, 100, 500, 400)
	                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
	                            NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
	                    backing:NSBackingStoreBuffered
	                      defer:NO];

	window.contentView = [[MetalView alloc] init];

	[window makeKeyAndOrderFront:nil];

	[NSApp activate];
}

@end

int
main(void)
{
	// setenv("MTL_SHADER_VALIDATION", "1", 1);
	// setenv("MTL_DEBUG_LAYER", "1", 1);
	// setenv("MTL_DEBUG_LAYER_WARNING_MODE", "nslog", 1);

	[NSApplication sharedApplication];
	AppDelegate *appDelegate = [[AppDelegate alloc] init];
	NSApp.delegate = appDelegate;
	[NSApp run];
}
