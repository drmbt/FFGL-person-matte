#include "AppleMonocularDepth.h"

#if defined( __APPLE__ )
#import <CoreML/CoreML.h>
#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>
#import <Vision/Vision.h>
#endif

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <limits>
#include <string>

using namespace ffglex;

enum ParamType : FFUInt32
{
	PT_OPACITY,
	PT_MODEL_MODE,
	PT_LOW_THRESHOLD,
	PT_HIGH_THRESHOLD,
	PT_MASK_MODE,
	PT_OUTPUT_MASK
};

static CFFGLPluginInfo PluginInfo(
	PluginFactory< AppleMonocularDepth >,
	"APMD",
	"Apple Monocular Depth",
	2,
	1,
	1,
	0,
	FF_EFFECT,
	"Apple Vision Core ML monocular depth matte",
	"Apple Vision FFGL"
);

static const char vertexShaderCode[] = R"(#version 410 core
uniform vec2 MaxUV;

layout( location = 0 ) in vec4 vPosition;
layout( location = 1 ) in vec2 vUV;

out vec2 uv;
out vec2 depthUV;

void main()
{
	gl_Position = vPosition;
	uv = vUV * MaxUV;
	depthUV = vec2( vUV.x, 1.0 - vUV.y );
}
)";

static const char fragmentShaderCode[] = R"(#version 410 core
uniform sampler2D InputTexture;
uniform sampler2D DepthTexture;
uniform float Opacity;
uniform float LowThreshold;
uniform float HighThreshold;
uniform float MaskMode;
uniform float OutputMask;
uniform int HasDepth;

in vec2 uv;
in vec2 depthUV;

out vec4 fragColor;

void main()
{
	vec4 color = texture( InputTexture, uv );

	if( HasDepth == 0 )
	{
		fragColor = color;
		return;
	}

	float depth = texture( DepthTexture, depthUV ).r;
	float low = min( LowThreshold, HighThreshold );
	float high = max( LowThreshold, HighThreshold );
	float band = step( low, depth ) * step( depth, high );

	if( OutputMask >= 0.5 )
	{
		fragColor = vec4( vec3( band ), band );
		return;
	}

	if( MaskMode >= 0.5 )
	{
		fragColor = vec4( color.rgb * band, color.a * band );
		return;
	}

	vec3 depthColor = vec3( depth );
	vec3 blended = mix( color.rgb, depthColor, Opacity );
	fragColor = vec4( blended, color.a * band );
}
)";

static float HalfToFloat( uint16_t value )
{
	const uint32_t sign = ( value & 0x8000u ) << 16;
	const uint32_t exponent = ( value & 0x7C00u ) >> 10;
	const uint32_t mantissa = value & 0x03FFu;

	uint32_t result = 0;
	if( exponent == 0 )
	{
		if( mantissa == 0 )
		{
			result = sign;
		}
		else
		{
			uint32_t normalizedMantissa = mantissa;
			uint32_t normalizedExponent = 113;
			while( ( normalizedMantissa & 0x0400u ) == 0 )
			{
				normalizedMantissa <<= 1;
				--normalizedExponent;
			}
			normalizedMantissa &= 0x03FFu;
			result = sign | ( normalizedExponent << 23 ) | ( normalizedMantissa << 13 );
		}
	}
	else if( exponent == 31 )
	{
		result = sign | 0x7F800000u | ( mantissa << 13 );
	}
	else
	{
		result = sign | ( ( exponent + 112 ) << 23 ) | ( mantissa << 13 );
	}

	float output = 0.0f;
	std::memcpy( &output, &result, sizeof( output ) );
	return output;
}

static void NormalizeFloatDepth( const std::vector< float >& source, size_t width, size_t height, std::vector< unsigned char >& dest )
{
	dest.assign( width * height, 0 );

	float minValue = std::numeric_limits< float >::max();
	float maxValue = std::numeric_limits< float >::lowest();
	for( float value : source )
	{
		if( !std::isfinite( value ) )
			continue;

		minValue = std::min( minValue, value );
		maxValue = std::max( maxValue, value );
	}

	const float range = maxValue - minValue;
	if( range <= std::numeric_limits< float >::epsilon() )
		return;

	for( size_t index = 0; index < source.size(); ++index )
	{
		const float value = source[ index ];
		if( !std::isfinite( value ) )
			continue;

		const float normalized = std::max( 0.0f, std::min( 1.0f, ( value - minValue ) / range ) );
		dest[ index ] = static_cast< unsigned char >( std::round( normalized * 255.0f ) );
	}
}

#if defined( __APPLE__ )
static const char* ModelModeName( unsigned int modelIndex )
{
	return modelIndex == 0 ? "Fast" : "Quality";
}

static NSURL* FindDepthModelURL( unsigned int modelIndex )
{
	NSBundle* bundle = [NSBundle bundleWithIdentifier:@"com.vincentnaples.ffgl.apple-monocular-depth"];
	if( bundle == nil )
		bundle = [NSBundle mainBundle];

	NSArray< NSString* >* preferredNames = modelIndex == 0 ?
		@[ @"DepthAnythingFast", @"DepthAnythingV2Small", @"DepthAnythingSmall", @"AppleMonocularDepthFast", @"DepthAnything", @"AppleMonocularDepth" ] :
		@[ @"DepthAnythingQuality", @"DepthAnythingV2Large", @"DepthAnythingLarge", @"DepthAnythingV2Base", @"DepthAnythingBase", @"AppleMonocularDepthQuality", @"DepthAnything", @"AppleMonocularDepth" ];
	for( NSString* modelName in preferredNames )
	{
		NSURL* modelURL = [bundle URLForResource:modelName withExtension:@"mlmodelc"];
		if( modelURL != nil )
			return modelURL;

		modelURL = [bundle URLForResource:modelName withExtension:@"mlpackage"];
		if( modelURL != nil )
			return modelURL;

		modelURL = [bundle URLForResource:modelName withExtension:@"mlmodel"];
		if( modelURL != nil )
			return modelURL;
	}

	NSString* resourcePath = [bundle resourcePath];
	if( resourcePath == nil )
		return nil;

	NSFileManager* fileManager = [NSFileManager defaultManager];
	NSArray< NSString* >* contents = [fileManager contentsOfDirectoryAtPath:resourcePath error:nil];
	for( NSString* entry in contents )
	{
		const bool isModel = [entry hasSuffix:@".mlmodelc"] || [entry hasSuffix:@".mlpackage"] || [entry hasSuffix:@".mlmodel"];
		if( !isModel )
			continue;

		NSString* lowerEntry = [entry lowercaseString];
		const bool isFast = [lowerEntry containsString:@"fast"] || [lowerEntry containsString:@"small"];
		const bool isQuality = [lowerEntry containsString:@"quality"] || [lowerEntry containsString:@"large"] || [lowerEntry containsString:@"base"];
		if( ( modelIndex == 0 && isFast ) || ( modelIndex == 1 && isQuality ) )
			return [NSURL fileURLWithPath:[resourcePath stringByAppendingPathComponent:entry]];
	}

	for( NSString* entry in contents )
	{
		const bool isModel = [entry hasSuffix:@".mlmodelc"] || [entry hasSuffix:@".mlpackage"] || [entry hasSuffix:@".mlmodel"];
		if( !isModel )
			continue;

		NSString* lowerEntry = [entry lowercaseString];
		const bool looksModeSpecific = [lowerEntry containsString:@"fast"] || [lowerEntry containsString:@"small"] ||
			[lowerEntry containsString:@"quality"] || [lowerEntry containsString:@"large"] || [lowerEntry containsString:@"base"];
		if( !looksModeSpecific )
			return [NSURL fileURLWithPath:[resourcePath stringByAppendingPathComponent:entry]];
	}

	return nil;
}

static std::string ModelLogPrefix( unsigned int modelIndex )
{
	return std::string( "Apple Monocular Depth " ) + ModelModeName( modelIndex ) + ": ";
}

static bool CopyPixelBufferDepth( CVPixelBufferRef pixelBuffer, unsigned int& width, unsigned int& height, std::vector< unsigned char >& pixels )
{
	if( pixelBuffer == nullptr )
		return false;

	CVPixelBufferLockBaseAddress( pixelBuffer, kCVPixelBufferLock_ReadOnly );

	const size_t pixelWidth = CVPixelBufferGetWidth( pixelBuffer );
	const size_t pixelHeight = CVPixelBufferGetHeight( pixelBuffer );
	const size_t bytesPerRow = CVPixelBufferGetBytesPerRow( pixelBuffer );
	const OSType pixelFormat = CVPixelBufferGetPixelFormatType( pixelBuffer );
	const unsigned char* baseAddress = static_cast< const unsigned char* >( CVPixelBufferGetBaseAddress( pixelBuffer ) );

	bool success = false;
	if( pixelWidth > 0 && pixelHeight > 0 && baseAddress != nullptr )
	{
		width = static_cast< unsigned int >( pixelWidth );
		height = static_cast< unsigned int >( pixelHeight );

		if( pixelFormat == kCVPixelFormatType_OneComponent8 )
		{
			pixels.resize( pixelWidth * pixelHeight );
			for( size_t y = 0; y < pixelHeight; ++y )
				std::memcpy( pixels.data() + y * pixelWidth, baseAddress + y * bytesPerRow, pixelWidth );
			success = true;
		}
		else if( pixelFormat == kCVPixelFormatType_OneComponent32Float || pixelFormat == kCVPixelFormatType_DepthFloat32 )
		{
			std::vector< float > floatPixels( pixelWidth * pixelHeight );
			for( size_t y = 0; y < pixelHeight; ++y )
			{
				const float* sourceRow = reinterpret_cast< const float* >( baseAddress + y * bytesPerRow );
				std::memcpy( floatPixels.data() + y * pixelWidth, sourceRow, pixelWidth * sizeof( float ) );
			}
			NormalizeFloatDepth( floatPixels, pixelWidth, pixelHeight, pixels );
			success = true;
		}
		else if( pixelFormat == kCVPixelFormatType_OneComponent16Half || pixelFormat == kCVPixelFormatType_DepthFloat16 )
		{
			std::vector< float > floatPixels( pixelWidth * pixelHeight );
			for( size_t y = 0; y < pixelHeight; ++y )
			{
				const uint16_t* sourceRow = reinterpret_cast< const uint16_t* >( baseAddress + y * bytesPerRow );
				for( size_t x = 0; x < pixelWidth; ++x )
					floatPixels[ y * pixelWidth + x ] = HalfToFloat( sourceRow[ x ] );
			}
			NormalizeFloatDepth( floatPixels, pixelWidth, pixelHeight, pixels );
			success = true;
		}
		else if( pixelFormat == kCVPixelFormatType_32BGRA || pixelFormat == kCVPixelFormatType_32RGBA )
		{
			pixels.resize( pixelWidth * pixelHeight );
			const bool bgra = pixelFormat == kCVPixelFormatType_32BGRA;
			for( size_t y = 0; y < pixelHeight; ++y )
			{
				const unsigned char* sourceRow = baseAddress + y * bytesPerRow;
				for( size_t x = 0; x < pixelWidth; ++x )
				{
					const unsigned char* sourcePixel = sourceRow + x * 4;
					const unsigned char r = bgra ? sourcePixel[ 2 ] : sourcePixel[ 0 ];
					const unsigned char g = sourcePixel[ 1 ];
					const unsigned char b = bgra ? sourcePixel[ 0 ] : sourcePixel[ 2 ];
					pixels[ y * pixelWidth + x ] = static_cast< unsigned char >( std::round( 0.2126f * r + 0.7152f * g + 0.0722f * b ) );
				}
			}
			success = true;
		}
	}

	CVPixelBufferUnlockBaseAddress( pixelBuffer, kCVPixelBufferLock_ReadOnly );
	return success;
}

static bool CopyMultiArrayDepth( MLMultiArray* multiArray, unsigned int& width, unsigned int& height, std::vector< unsigned char >& pixels )
{
	if( multiArray == nil || multiArray.shape.count < 2 || multiArray.dataPointer == nullptr )
		return false;

	const NSInteger rank = multiArray.shape.count;
	const NSInteger arrayHeight = [[multiArray.shape objectAtIndex:rank - 2] integerValue];
	const NSInteger arrayWidth = [[multiArray.shape objectAtIndex:rank - 1] integerValue];
	if( arrayWidth <= 0 || arrayHeight <= 0 )
		return false;

	const NSInteger yStride = [[multiArray.strides objectAtIndex:rank - 2] integerValue];
	const NSInteger xStride = [[multiArray.strides objectAtIndex:rank - 1] integerValue];
	std::vector< float > floatPixels( static_cast< size_t >( arrayWidth ) * static_cast< size_t >( arrayHeight ) );

	switch( multiArray.dataType )
	{
	case MLMultiArrayDataTypeDouble:
	{
		const double* data = static_cast< const double* >( multiArray.dataPointer );
		for( NSInteger y = 0; y < arrayHeight; ++y )
			for( NSInteger x = 0; x < arrayWidth; ++x )
				floatPixels[ static_cast< size_t >( y * arrayWidth + x ) ] = static_cast< float >( data[ y * yStride + x * xStride ] );
		break;
	}
	case MLMultiArrayDataTypeFloat32:
	{
		const float* data = static_cast< const float* >( multiArray.dataPointer );
		for( NSInteger y = 0; y < arrayHeight; ++y )
			for( NSInteger x = 0; x < arrayWidth; ++x )
				floatPixels[ static_cast< size_t >( y * arrayWidth + x ) ] = data[ y * yStride + x * xStride ];
		break;
	}
	case MLMultiArrayDataTypeFloat16:
	{
		const uint16_t* data = static_cast< const uint16_t* >( multiArray.dataPointer );
		for( NSInteger y = 0; y < arrayHeight; ++y )
			for( NSInteger x = 0; x < arrayWidth; ++x )
				floatPixels[ static_cast< size_t >( y * arrayWidth + x ) ] = HalfToFloat( data[ y * yStride + x * xStride ] );
		break;
	}
	case MLMultiArrayDataTypeInt32:
	{
		const int32_t* data = static_cast< const int32_t* >( multiArray.dataPointer );
		for( NSInteger y = 0; y < arrayHeight; ++y )
			for( NSInteger x = 0; x < arrayWidth; ++x )
				floatPixels[ static_cast< size_t >( y * arrayWidth + x ) ] = static_cast< float >( data[ y * yStride + x * xStride ] );
		break;
	}
	default:
		return false;
	}

	width = static_cast< unsigned int >( arrayWidth );
	height = static_cast< unsigned int >( arrayHeight );
	NormalizeFloatDepth( floatPixels, static_cast< size_t >( arrayWidth ), static_cast< size_t >( arrayHeight ), pixels );
	return true;
}
#endif

AppleMonocularDepth::AppleMonocularDepth() :
	depthTexture( 0 ),
	depthWidth( 0 ),
	depthHeight( 0 ),
	hasDepth( false ),
	opacity( 1.0f ),
	modelMode( 0.0f ),
	lowThreshold( 0.0f ),
	highThreshold( 1.0f ),
	maskMode( 0.0f ),
	outputMask( 0.0f )
{
	for( unsigned int index = 0; index < 2; ++index )
	{
		loggedModelSuccess[ index ] = false;
		loggedModelFailure[ index ] = false;
		loggedModelUnavailable[ index ] = false;
		loggedVisionFailure[ index ] = false;
		coreMLModels[ index ] = nullptr;
	}

	SetMinInputs( 1 );
	SetMaxInputs( 1 );

	SetParamInfof( PT_OPACITY, "Opacity", FF_TYPE_STANDARD );
	SetOptionParamInfo( PT_MODEL_MODE, "Model", 2, modelMode );
	SetParamElementInfo( PT_MODEL_MODE, 0, "Fast", 0.0f );
	SetParamElementInfo( PT_MODEL_MODE, 1, "Quality", 1.0f );
	SetParamInfof( PT_LOW_THRESHOLD, "Low", FF_TYPE_STANDARD );
	SetParamInfof( PT_HIGH_THRESHOLD, "High", FF_TYPE_STANDARD );
	SetParamInfo( PT_MASK_MODE, "Mask Mode", FF_TYPE_BOOLEAN, false );
	SetParamInfo( PT_OUTPUT_MASK, "Output Mask", FF_TYPE_BOOLEAN, false );

	FFGLLog::LogToHost( "Created Apple Monocular Depth effect" );
}

AppleMonocularDepth::~AppleMonocularDepth()
{
	DeInitGL();
}

FFResult AppleMonocularDepth::InitGL( const FFGLViewportStruct* vp )
{
	if( !shader.Compile( vertexShaderCode, fragmentShaderCode ) )
	{
		DeInitGL();
		return FF_FAIL;
	}

	if( !quad.Initialise() )
	{
		DeInitGL();
		return FF_FAIL;
	}

	glGenTextures( 1, &depthTexture );
	glBindTexture( GL_TEXTURE_2D, depthTexture );
	glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR );
	glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR );
	glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE );
	glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE );
	glBindTexture( GL_TEXTURE_2D, 0 );

	return CFFGLPlugin::InitGL( vp );
}

FFResult AppleMonocularDepth::ProcessOpenGL( ProcessOpenGLStruct* pGL )
{
	if( pGL->numInputTextures < 1 )
		return FF_FAIL;

	if( pGL->inputTextures[ 0 ] == NULL )
		return FF_FAIL;

	const FFGLTextureStruct& inputTexture = *pGL->inputTextures[ 0 ];
	UpdateDepthTexture( inputTexture );

	ScopedShaderBinding shaderBinding( shader.GetGLID() );
	ScopedSamplerActivation activateInputSampler( 0 );
	Scoped2DTextureBinding textureBinding( inputTexture.Handle );

	shader.Set( "InputTexture", 0 );

	FFGLTexCoords maxCoords = GetMaxGLTexCoords( inputTexture );
	shader.Set( "MaxUV", maxCoords.s, maxCoords.t );

	ScopedSamplerActivation activateDepthSampler( 1 );
	Scoped2DTextureBinding depthBinding( depthTexture );
	shader.Set( "DepthTexture", 1 );

	shader.Set( "Opacity", opacity );
	shader.Set( "LowThreshold", lowThreshold );
	shader.Set( "HighThreshold", highThreshold );
	shader.Set( "MaskMode", maskMode );
	shader.Set( "OutputMask", outputMask );
	shader.Set( "HasDepth", hasDepth ? 1 : 0 );

	quad.Draw();

	return FF_SUCCESS;
}

FFResult AppleMonocularDepth::DeInitGL()
{
	shader.FreeGLResources();
	quad.Release();
	ReleaseDepthTexture();
	ReleaseDepthModels();
	return FF_SUCCESS;
}

FFResult AppleMonocularDepth::SetFloatParameter( unsigned int dwIndex, float value )
{
	switch( dwIndex )
	{
	case PT_OPACITY:
		opacity = value;
		break;
	case PT_MODEL_MODE:
		modelMode = value < 0.5f ? 0.0f : 1.0f;
		hasDepth = false;
		break;
	case PT_LOW_THRESHOLD:
		lowThreshold = value;
		break;
	case PT_HIGH_THRESHOLD:
		highThreshold = value;
		break;
	case PT_MASK_MODE:
		maskMode = value >= 0.5f ? 1.0f : 0.0f;
		break;
	case PT_OUTPUT_MASK:
		outputMask = value >= 0.5f ? 1.0f : 0.0f;
		break;
	default:
		return FF_FAIL;
	}

	return FF_SUCCESS;
}

float AppleMonocularDepth::GetFloatParameter( unsigned int index )
{
	switch( index )
	{
	case PT_OPACITY:
		return opacity;
	case PT_MODEL_MODE:
		return modelMode;
	case PT_LOW_THRESHOLD:
		return lowThreshold;
	case PT_HIGH_THRESHOLD:
		return highThreshold;
	case PT_MASK_MODE:
		return maskMode;
	case PT_OUTPUT_MASK:
		return outputMask;
	}

	return 0.0f;
}

bool AppleMonocularDepth::UpdateDepthTexture( const FFGLTextureStruct& inputTexture )
{
	if( !GenerateDepthMap( inputTexture ) )
	{
		hasDepth = false;
		return false;
	}

	GLint previousUnpackAlignment = 0;
	glGetIntegerv( GL_UNPACK_ALIGNMENT, &previousUnpackAlignment );
	glPixelStorei( GL_UNPACK_ALIGNMENT, 1 );

	glBindTexture( GL_TEXTURE_2D, depthTexture );
	glTexImage2D( GL_TEXTURE_2D, 0, GL_R8, depthWidth, depthHeight, 0, GL_RED, GL_UNSIGNED_BYTE, depthPixels.data() );
	glBindTexture( GL_TEXTURE_2D, 0 );

	glPixelStorei( GL_UNPACK_ALIGNMENT, previousUnpackAlignment );
	hasDepth = true;
	return true;
}

bool AppleMonocularDepth::GenerateDepthMap( const FFGLTextureStruct& inputTexture )
{
#if defined( __APPLE__ )
	if( inputTexture.Width == 0 || inputTexture.Height == 0 || inputTexture.HardwareWidth == 0 || inputTexture.HardwareHeight == 0 )
		return false;

	const unsigned int modelIndex = modelMode < 0.5f ? 0u : 1u;
	if( !EnsureDepthModelLoaded( modelIndex ) )
		return false;

	const size_t hardwareWidth = inputTexture.HardwareWidth;
	const size_t hardwareHeight = inputTexture.HardwareHeight;
	const size_t width = inputTexture.Width;
	const size_t height = inputTexture.Height;

	rgbaPixels.resize( hardwareWidth * hardwareHeight * 4 );
	bgraPixels.resize( width * height * 4 );

	GLint previousPackAlignment = 0;
	glGetIntegerv( GL_PACK_ALIGNMENT, &previousPackAlignment );
	glPixelStorei( GL_PACK_ALIGNMENT, 1 );
	glBindTexture( GL_TEXTURE_2D, inputTexture.Handle );
	glGetTexImage( GL_TEXTURE_2D, 0, GL_RGBA, GL_UNSIGNED_BYTE, rgbaPixels.data() );
	glBindTexture( GL_TEXTURE_2D, 0 );
	glPixelStorei( GL_PACK_ALIGNMENT, previousPackAlignment );

	for( size_t y = 0; y < height; ++y )
	{
		const size_t sourceY = height - 1 - y;
		const unsigned char* sourceRow = rgbaPixels.data() + ( sourceY * hardwareWidth * 4 );
		unsigned char* destRow = bgraPixels.data() + ( y * width * 4 );

		for( size_t x = 0; x < width; ++x )
		{
			const unsigned char* sourcePixel = sourceRow + ( x * 4 );
			unsigned char* destPixel = destRow + ( x * 4 );
			destPixel[ 0 ] = sourcePixel[ 2 ];
			destPixel[ 1 ] = sourcePixel[ 1 ];
			destPixel[ 2 ] = sourcePixel[ 0 ];
			destPixel[ 3 ] = sourcePixel[ 3 ];
		}
	}

	CVPixelBufferRef sourceBuffer = nullptr;
	CVReturn cvResult = CVPixelBufferCreate( kCFAllocatorDefault,
											 width,
											 height,
											 kCVPixelFormatType_32BGRA,
											 nullptr,
											 &sourceBuffer );
	if( cvResult != kCVReturnSuccess || sourceBuffer == nullptr )
	{
		if( !loggedVisionFailure[ modelIndex ] )
		{
			const std::string message = ModelLogPrefix( modelIndex ) + "failed to create CVPixelBuffer for Vision input";
			FFGLLog::LogToHost( message.c_str() );
			loggedVisionFailure[ modelIndex ] = true;
		}
		return false;
	}

	CVPixelBufferLockBaseAddress( sourceBuffer, 0 );
	unsigned char* baseAddress = static_cast< unsigned char* >( CVPixelBufferGetBaseAddress( sourceBuffer ) );
	const size_t bytesPerRow = CVPixelBufferGetBytesPerRow( sourceBuffer );
	for( size_t y = 0; y < height; ++y )
		std::memcpy( baseAddress + y * bytesPerRow, bgraPixels.data() + y * width * 4, width * 4 );
	CVPixelBufferUnlockBaseAddress( sourceBuffer, 0 );

	bool success = false;

	@autoreleasepool
	{
		VNCoreMLModel* model = (VNCoreMLModel*)coreMLModels[ modelIndex ];
		VNCoreMLRequest* request = [[VNCoreMLRequest alloc] initWithModel:model];
		request.imageCropAndScaleOption = VNImageCropAndScaleOptionScaleFill;

		NSError* error = nil;
		VNImageRequestHandler* handler = [[VNImageRequestHandler alloc] initWithCVPixelBuffer:sourceBuffer options:@{}];
		BOOL performed = [handler performRequests:@[ request ] error:&error];

		if( performed && request.results.count > 0 )
		{
			id observation = request.results.firstObject;
			if( [observation isKindOfClass:[VNPixelBufferObservation class]] )
			{
				success = CopyPixelBufferDepth( ( (VNPixelBufferObservation*)observation ).pixelBuffer, depthWidth, depthHeight, depthPixels );
			}
			else if( [observation isKindOfClass:[VNCoreMLFeatureValueObservation class]] )
			{
				MLFeatureValue* featureValue = ( (VNCoreMLFeatureValueObservation*)observation ).featureValue;
				success = CopyMultiArrayDepth( featureValue.multiArrayValue, depthWidth, depthHeight, depthPixels );
			}

			if( success && !loggedModelSuccess[ modelIndex ] )
			{
				const std::string message = ModelLogPrefix( modelIndex ) + "Core ML depth active, input " +
					std::to_string( width ) + "x" + std::to_string( height ) +
					", depth " + std::to_string( depthWidth ) + "x" + std::to_string( depthHeight );
				FFGLLog::LogToHost( message.c_str() );
				loggedModelSuccess[ modelIndex ] = true;
			}
		}
		else if( !loggedVisionFailure[ modelIndex ] )
		{
			std::string message = ModelLogPrefix( modelIndex ) + "Vision Core ML request failed or returned no depth";
			if( error != nil && error.localizedDescription != nil )
				message += std::string( ": " ) + [error.localizedDescription UTF8String];
			FFGLLog::LogToHost( message.c_str() );
			loggedVisionFailure[ modelIndex ] = true;
		}

		[handler release];
		[request release];
	}

	CVPixelBufferRelease( sourceBuffer );
	return success;
#endif

	return false;
}

bool AppleMonocularDepth::EnsureDepthModelLoaded( unsigned int modelIndex )
{
#if defined( __APPLE__ )
	modelIndex = modelIndex == 0 ? 0 : 1;

	if( coreMLModels[ modelIndex ] != nullptr )
		return true;

	@autoreleasepool
	{
		NSURL* modelURL = FindDepthModelURL( modelIndex );
		if( modelURL == nil )
		{
			if( !loggedModelUnavailable[ modelIndex ] )
			{
				const std::string message = ModelLogPrefix( modelIndex ) + "add DepthAnythingFast.mlmodelc and DepthAnythingQuality.mlmodelc to the plugin bundle Resources folder";
				FFGLLog::LogToHost( message.c_str() );
				loggedModelUnavailable[ modelIndex ] = true;
			}
			return false;
		}

		NSError* error = nil;
		NSURL* loadURL = modelURL;
		NSString* modelExtension = [[modelURL pathExtension] lowercaseString];
		if( [modelExtension isEqualToString:@"mlmodel"] || [modelExtension isEqualToString:@"mlpackage"] )
		{
			loadURL = [MLModel compileModelAtURL:modelURL error:&error];
			if( loadURL == nil )
			{
				if( !loggedModelFailure[ modelIndex ] )
				{
					std::string message = ModelLogPrefix( modelIndex ) + "failed to compile Core ML model";
					if( error != nil && error.localizedDescription != nil )
						message += std::string( ": " ) + [error.localizedDescription UTF8String];
					FFGLLog::LogToHost( message.c_str() );
					loggedModelFailure[ modelIndex ] = true;
				}
				return false;
			}
		}

		MLModelConfiguration* configuration = [[MLModelConfiguration alloc] init];
		configuration.computeUnits = MLComputeUnitsAll;

		MLModel* mlModel = [MLModel modelWithContentsOfURL:loadURL configuration:configuration error:&error];
		if( mlModel == nil )
		{
			if( !loggedModelFailure[ modelIndex ] )
			{
				std::string message = ModelLogPrefix( modelIndex ) + "failed to load Core ML model";
				if( error != nil && error.localizedDescription != nil )
					message += std::string( ": " ) + [error.localizedDescription UTF8String];
				FFGLLog::LogToHost( message.c_str() );
				loggedModelFailure[ modelIndex ] = true;
			}
			[configuration release];
			return false;
		}

		VNCoreMLModel* visionModel = [VNCoreMLModel modelForMLModel:mlModel error:&error];
		if( visionModel == nil )
		{
			if( !loggedModelFailure[ modelIndex ] )
			{
				std::string message = ModelLogPrefix( modelIndex ) + "failed to wrap Core ML model for Vision";
				if( error != nil && error.localizedDescription != nil )
					message += std::string( ": " ) + [error.localizedDescription UTF8String];
				FFGLLog::LogToHost( message.c_str() );
				loggedModelFailure[ modelIndex ] = true;
			}
			[configuration release];
			return false;
		}

		coreMLModels[ modelIndex ] = [visionModel retain];
		[configuration release];
		return true;
	}
#endif

	return false;
}

void AppleMonocularDepth::ReleaseDepthTexture()
{
	if( depthTexture != 0 )
	{
		glDeleteTextures( 1, &depthTexture );
		depthTexture = 0;
	}

	depthWidth = 0;
	depthHeight = 0;
	hasDepth = false;
}

void AppleMonocularDepth::ReleaseDepthModels()
{
#if defined( __APPLE__ )
	for( unsigned int index = 0; index < 2; ++index )
	{
		if( coreMLModels[ index ] != nullptr )
		{
			[(id)coreMLModels[ index ] release];
			coreMLModels[ index ] = nullptr;
		}
	}
#endif
}
