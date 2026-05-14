#include "ApplePersonSegmentation.h"

#if defined( __APPLE__ )
#import <Foundation/Foundation.h>
#import <Vision/Vision.h>
#import <CoreVideo/CoreVideo.h>
#endif

#include <algorithm>
#include <cstring>
#include <string>

using namespace ffglex;

enum ParamType : FFUInt32
{
	PT_THRESHOLD,
	PT_SOFTNESS,
	PT_SHRINK_GROW,
	PT_FEATHER,
	PT_OPACITY,
	PT_INVERT,
	PT_SHOW_MASK,
	PT_QUALITY,
	PT_OUTPUT_MODE
};

static CFFGLPluginInfo PluginInfo(
	PluginFactory< ApplePersonSegmentation >,
	"APSG",
	"Apple Person Segmentation",
	2,
	1,
	1,
	0,
	FF_EFFECT,
	"Apple Vision person matte for live video",
	"Apple Vision FFGL"
);

static const char vertexShaderCode[] = R"(#version 410 core
uniform vec2 MaxUV;

layout( location = 0 ) in vec4 vPosition;
layout( location = 1 ) in vec2 vUV;

out vec2 uv;
out vec2 maskUV;

void main()
{
	gl_Position = vPosition;
	uv = vUV * MaxUV;
	maskUV = vec2( vUV.x, 1.0 - vUV.y );
}
)";

static const char fragmentShaderCode[] = R"(#version 410 core
uniform sampler2D InputTexture;
uniform sampler2D MaskTexture;
uniform float Threshold;
uniform float Softness;
uniform float ShrinkGrow;
uniform float Feather;
uniform float Opacity;
uniform float InvertMask;
uniform float ShowMask;
uniform int OutputMode;
uniform int HasMask;
uniform vec2 MaskSize;

in vec2 uv;
in vec2 maskUV;

out vec4 fragColor;

float sampleMask( vec2 coord )
{
	return texture( MaskTexture, clamp( coord, vec2( 0.0 ), vec2( 1.0 ) ) ).r;
}

void accumulateMorphSample( inout float result, vec2 coord, vec2 offset, float radius, vec2 texel, float amount )
{
	float sampled = sampleMask( coord + offset * texel * radius );
	result = amount > 0.0 ? max( result, sampled ) : min( result, sampled );
}

float morphMask( vec2 coord )
{
	float amount = clamp( ShrinkGrow * 2.0 - 1.0, -1.0, 1.0 );
	float radius = amount > 0.0 ? amount * 32.0 : -amount * 18.0;
	float result = sampleMask( coord );

	if( radius < 0.001 )
		return result;

	vec2 texel = 1.0 / max( MaskSize, vec2( 1.0 ) );
	accumulateMorphSample( result, coord, vec2( 1.0, 0.0 ), radius, texel, amount );
	accumulateMorphSample( result, coord, vec2( -1.0, 0.0 ), radius, texel, amount );
	accumulateMorphSample( result, coord, vec2( 0.0, 1.0 ), radius, texel, amount );
	accumulateMorphSample( result, coord, vec2( 0.0, -1.0 ), radius, texel, amount );
	accumulateMorphSample( result, coord, vec2( 0.7071, 0.7071 ), radius, texel, amount );
	accumulateMorphSample( result, coord, vec2( -0.7071, 0.7071 ), radius, texel, amount );
	accumulateMorphSample( result, coord, vec2( 0.7071, -0.7071 ), radius, texel, amount );
	accumulateMorphSample( result, coord, vec2( -0.7071, -0.7071 ), radius, texel, amount );
	accumulateMorphSample( result, coord, vec2( 0.5, 0.0 ), radius, texel, amount );
	accumulateMorphSample( result, coord, vec2( -0.5, 0.0 ), radius, texel, amount );
	accumulateMorphSample( result, coord, vec2( 0.0, 0.5 ), radius, texel, amount );
	accumulateMorphSample( result, coord, vec2( 0.0, -0.5 ), radius, texel, amount );
	accumulateMorphSample( result, coord, vec2( 0.3536, 0.3536 ), radius, texel, amount );
	accumulateMorphSample( result, coord, vec2( -0.3536, 0.3536 ), radius, texel, amount );
	accumulateMorphSample( result, coord, vec2( 0.3536, -0.3536 ), radius, texel, amount );
	accumulateMorphSample( result, coord, vec2( -0.3536, -0.3536 ), radius, texel, amount );

	return result;
}

void accumulateFeatherSample( inout float mask, inout float weight, vec2 coord, vec2 offset, float radius, vec2 texel, float sampleWeight )
{
	mask += morphMask( coord + offset * texel * radius ) * sampleWeight;
	weight += sampleWeight;
}

float featherMask( vec2 coord )
{
	float radius = clamp( Feather, 0.0, 1.0 ) * 24.0;
	float center = morphMask( coord );

	if( radius < 0.001 )
		return center;

	vec2 texel = 1.0 / max( MaskSize, vec2( 1.0 ) );
	float mask = center * 4.0;
	float weight = 4.0;

	accumulateFeatherSample( mask, weight, coord, vec2( 1.0, 0.0 ), radius * 0.5, texel, 2.0 );
	accumulateFeatherSample( mask, weight, coord, vec2( -1.0, 0.0 ), radius * 0.5, texel, 2.0 );
	accumulateFeatherSample( mask, weight, coord, vec2( 0.0, 1.0 ), radius * 0.5, texel, 2.0 );
	accumulateFeatherSample( mask, weight, coord, vec2( 0.0, -1.0 ), radius * 0.5, texel, 2.0 );
	accumulateFeatherSample( mask, weight, coord, vec2( 0.7071, 0.7071 ), radius * 0.5, texel, 2.0 );
	accumulateFeatherSample( mask, weight, coord, vec2( -0.7071, 0.7071 ), radius * 0.5, texel, 2.0 );
	accumulateFeatherSample( mask, weight, coord, vec2( 0.7071, -0.7071 ), radius * 0.5, texel, 2.0 );
	accumulateFeatherSample( mask, weight, coord, vec2( -0.7071, -0.7071 ), radius * 0.5, texel, 2.0 );

	accumulateFeatherSample( mask, weight, coord, vec2( 1.0, 0.0 ), radius, texel, 1.0 );
	accumulateFeatherSample( mask, weight, coord, vec2( -1.0, 0.0 ), radius, texel, 1.0 );
	accumulateFeatherSample( mask, weight, coord, vec2( 0.0, 1.0 ), radius, texel, 1.0 );
	accumulateFeatherSample( mask, weight, coord, vec2( 0.0, -1.0 ), radius, texel, 1.0 );
	accumulateFeatherSample( mask, weight, coord, vec2( 0.7071, 0.7071 ), radius, texel, 1.0 );
	accumulateFeatherSample( mask, weight, coord, vec2( -0.7071, 0.7071 ), radius, texel, 1.0 );
	accumulateFeatherSample( mask, weight, coord, vec2( 0.7071, -0.7071 ), radius, texel, 1.0 );
	accumulateFeatherSample( mask, weight, coord, vec2( -0.7071, -0.7071 ), radius, texel, 1.0 );

	return mask / weight;
}

void main()
{
	vec4 color = texture( InputTexture, uv );

	if( HasMask == 0 )
	{
		fragColor = color;
		return;
	}

	float mask = featherMask( maskUV );
	mask = mix( mask, 1.0 - mask, step( 0.5, InvertMask ) );

	float soft = max( Softness, 0.001 );
	mask = smoothstep( Threshold - soft, Threshold + soft, mask ) * Opacity;

	if( ShowMask >= 0.5 )
	{
		fragColor = vec4( vec3( mask ), 1.0 );
		return;
	}

	float outputAlpha = color.a * mask;

	if( OutputMode == 1 )
	{
		fragColor = vec4( color.rgb, outputAlpha );
		return;
	}

	if( color.a > 0.0 )
		color.rgb /= color.a;

	fragColor = vec4( color.rgb * outputAlpha, outputAlpha );
}
)";

ApplePersonSegmentation::ApplePersonSegmentation() :
	maskTexture( 0 ),
	maskWidth( 0 ),
	maskHeight( 0 ),
	hasMask( false ),
	loggedVisionSuccess( false ),
	loggedVisionFailure( false ),
	loggedVisionUnavailable( false ),
	threshold( 0.5f ),
	softness( 0.1f ),
	shrinkGrow( 0.5f ),
	feather( 0.0f ),
	opacity( 1.0f ),
	invertMask( 0.0f ),
	showMask( 0.0f ),
	quality( 0.5f ),
	outputMode( 0.0f )
{
	SetMinInputs( 1 );
	SetMaxInputs( 1 );

	SetParamInfof( PT_THRESHOLD, "Threshold", FF_TYPE_STANDARD );
	SetParamInfof( PT_SOFTNESS, "Softness", FF_TYPE_STANDARD );
	SetParamInfof( PT_SHRINK_GROW, "Shrink / Grow", FF_TYPE_STANDARD );
	SetParamInfof( PT_FEATHER, "Feather", FF_TYPE_STANDARD );
	SetParamInfof( PT_OPACITY, "Opacity", FF_TYPE_STANDARD );
	SetParamInfo( PT_INVERT, "Invert Mask", FF_TYPE_BOOLEAN, false );
	SetParamInfo( PT_SHOW_MASK, "Show Mask", FF_TYPE_BOOLEAN, false );
	SetParamInfof( PT_QUALITY, "Quality", FF_TYPE_STANDARD );
	SetOptionParamInfo( PT_OUTPUT_MODE, "Output Mode", 2, outputMode );
	SetParamElementInfo( PT_OUTPUT_MODE, 0, "Premult Alpha", 0.0f );
	SetParamElementInfo( PT_OUTPUT_MODE, 1, "Straight Alpha", 1.0f );

	FFGLLog::LogToHost( "Created Apple Person Segmentation effect" );
}

ApplePersonSegmentation::~ApplePersonSegmentation()
{
	DeInitGL();
}

FFResult ApplePersonSegmentation::InitGL( const FFGLViewportStruct* vp )
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

	glGenTextures( 1, &maskTexture );
	glBindTexture( GL_TEXTURE_2D, maskTexture );
	glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR );
	glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR );
	glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE );
	glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE );
	glBindTexture( GL_TEXTURE_2D, 0 );

	return CFFGLPlugin::InitGL( vp );
}

FFResult ApplePersonSegmentation::ProcessOpenGL( ProcessOpenGLStruct* pGL )
{
	if( pGL->numInputTextures < 1 )
		return FF_FAIL;

	if( pGL->inputTextures[ 0 ] == NULL )
		return FF_FAIL;

	const FFGLTextureStruct& inputTexture = *pGL->inputTextures[ 0 ];
	UpdateMaskTexture( inputTexture );

	ScopedShaderBinding shaderBinding( shader.GetGLID() );
	ScopedSamplerActivation activateInputSampler( 0 );
	Scoped2DTextureBinding textureBinding( inputTexture.Handle );

	shader.Set( "InputTexture", 0 );

	FFGLTexCoords maxCoords = GetMaxGLTexCoords( inputTexture );
	shader.Set( "MaxUV", maxCoords.s, maxCoords.t );

	ScopedSamplerActivation activateMaskSampler( 1 );
	Scoped2DTextureBinding maskBinding( maskTexture );
	shader.Set( "MaskTexture", 1 );

	shader.Set( "Threshold", threshold );
	shader.Set( "Softness", softness );
	shader.Set( "ShrinkGrow", shrinkGrow );
	shader.Set( "Feather", feather );
	shader.Set( "Opacity", opacity );
	shader.Set( "InvertMask", invertMask );
	shader.Set( "ShowMask", showMask );
	shader.Set( "OutputMode", static_cast< int >( outputMode + 0.5f ) );
	shader.Set( "HasMask", hasMask ? 1 : 0 );
	shader.Set( "MaskSize", static_cast< float >( maskWidth ), static_cast< float >( maskHeight ) );

	quad.Draw();

	return FF_SUCCESS;
}

FFResult ApplePersonSegmentation::DeInitGL()
{
	shader.FreeGLResources();
	quad.Release();
	ReleaseMaskTexture();
	return FF_SUCCESS;
}

FFResult ApplePersonSegmentation::SetFloatParameter( unsigned int dwIndex, float value )
{
	switch( dwIndex )
	{
	case PT_THRESHOLD:
		threshold = value;
		break;
	case PT_SOFTNESS:
		softness = value;
		break;
	case PT_SHRINK_GROW:
		shrinkGrow = std::max( 0.0f, std::min( value, 1.0f ) );
		break;
	case PT_FEATHER:
		feather = std::max( 0.0f, std::min( value, 1.0f ) );
		break;
	case PT_OPACITY:
		opacity = value;
		break;
	case PT_INVERT:
		invertMask = value >= 0.5f ? 1.0f : 0.0f;
		break;
	case PT_SHOW_MASK:
		showMask = value >= 0.5f ? 1.0f : 0.0f;
		break;
	case PT_QUALITY:
		quality = value;
		break;
	case PT_OUTPUT_MODE:
		outputMode = value < 0.5f ? 0.0f : 1.0f;
		break;
	default:
		return FF_FAIL;
	}

	return FF_SUCCESS;
}

float ApplePersonSegmentation::GetFloatParameter( unsigned int index )
{
	switch( index )
	{
	case PT_THRESHOLD:
		return threshold;
	case PT_SOFTNESS:
		return softness;
	case PT_SHRINK_GROW:
		return shrinkGrow;
	case PT_FEATHER:
		return feather;
	case PT_OPACITY:
		return opacity;
	case PT_INVERT:
		return invertMask;
	case PT_SHOW_MASK:
		return showMask;
	case PT_QUALITY:
		return quality;
	case PT_OUTPUT_MODE:
		return outputMode;
	}

	return 0.0f;
}

bool ApplePersonSegmentation::UpdateMaskTexture( const FFGLTextureStruct& inputTexture )
{
	if( !GeneratePersonMask( inputTexture ) )
	{
		hasMask = false;
		return false;
	}

	GLint previousUnpackAlignment = 0;
	glGetIntegerv( GL_UNPACK_ALIGNMENT, &previousUnpackAlignment );
	glPixelStorei( GL_UNPACK_ALIGNMENT, 1 );

	glBindTexture( GL_TEXTURE_2D, maskTexture );
	glTexImage2D( GL_TEXTURE_2D, 0, GL_R8, maskWidth, maskHeight, 0, GL_RED, GL_UNSIGNED_BYTE, maskPixels.data() );
	glBindTexture( GL_TEXTURE_2D, 0 );

	glPixelStorei( GL_UNPACK_ALIGNMENT, previousUnpackAlignment );
	hasMask = true;
	return true;
}

bool ApplePersonSegmentation::GeneratePersonMask( const FFGLTextureStruct& inputTexture )
{
#if defined( __APPLE__ )
	if( inputTexture.Width == 0 || inputTexture.Height == 0 || inputTexture.HardwareWidth == 0 || inputTexture.HardwareHeight == 0 )
		return false;

	if( @available( macOS 12.0, * ) )
	{
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
			if( !loggedVisionFailure )
			{
				FFGLLog::LogToHost( "Apple Person Segmentation: failed to create CVPixelBuffer for Vision input" );
				loggedVisionFailure = true;
			}
			return false;
		}

		CVPixelBufferLockBaseAddress( sourceBuffer, 0 );
		unsigned char* baseAddress = static_cast< unsigned char* >( CVPixelBufferGetBaseAddress( sourceBuffer ) );
		const size_t bytesPerRow = CVPixelBufferGetBytesPerRow( sourceBuffer );
		for( size_t y = 0; y < height; ++y )
		{
			std::memcpy( baseAddress + y * bytesPerRow, bgraPixels.data() + y * width * 4, width * 4 );
		}
		CVPixelBufferUnlockBaseAddress( sourceBuffer, 0 );

		bool success = false;

		@autoreleasepool
		{
			VNGeneratePersonSegmentationRequest* request = [[VNGeneratePersonSegmentationRequest alloc] init];
			request.outputPixelFormat = kCVPixelFormatType_OneComponent8;

			if( quality < 0.33f )
				request.qualityLevel = VNGeneratePersonSegmentationRequestQualityLevelFast;
			else if( quality < 0.66f )
				request.qualityLevel = VNGeneratePersonSegmentationRequestQualityLevelBalanced;
			else
				request.qualityLevel = VNGeneratePersonSegmentationRequestQualityLevelAccurate;

			NSError* error = nil;
			VNImageRequestHandler* handler = [[VNImageRequestHandler alloc] initWithCVPixelBuffer:sourceBuffer options:@{}];
			BOOL performed = [handler performRequests:@[ request ] error:&error];

			if( performed && request.results.count > 0 )
			{
				VNPixelBufferObservation* observation = static_cast< VNPixelBufferObservation* >( request.results.firstObject );
				CVPixelBufferRef matteBuffer = observation.pixelBuffer;

				CVPixelBufferLockBaseAddress( matteBuffer, kCVPixelBufferLock_ReadOnly );
				const size_t matteWidth = CVPixelBufferGetWidth( matteBuffer );
				const size_t matteHeight = CVPixelBufferGetHeight( matteBuffer );
				const size_t matteBytesPerRow = CVPixelBufferGetBytesPerRow( matteBuffer );
				const unsigned char* matteBaseAddress = static_cast< const unsigned char* >( CVPixelBufferGetBaseAddress( matteBuffer ) );

				if( matteWidth > 0 && matteHeight > 0 && matteBaseAddress != nullptr )
				{
					maskWidth = static_cast< unsigned int >( matteWidth );
					maskHeight = static_cast< unsigned int >( matteHeight );
					maskPixels.resize( matteWidth * matteHeight );
					for( size_t y = 0; y < matteHeight; ++y )
					{
						std::memcpy( maskPixels.data() + y * matteWidth, matteBaseAddress + y * matteBytesPerRow, matteWidth );
					}

					if( !loggedVisionSuccess )
					{
						const std::string message = "Apple Person Segmentation: Vision matte active, input " +
							std::to_string( width ) + "x" + std::to_string( height ) +
							", matte " + std::to_string( matteWidth ) + "x" + std::to_string( matteHeight );
						FFGLLog::LogToHost( message.c_str() );
						loggedVisionSuccess = true;
					}
					success = true;
				}

				CVPixelBufferUnlockBaseAddress( matteBuffer, kCVPixelBufferLock_ReadOnly );
			}
			else if( !loggedVisionFailure )
			{
				std::string message = "Apple Person Segmentation: Vision request failed or returned no matte";
				if( error != nil && error.localizedDescription != nil )
					message += std::string( ": " ) + [error.localizedDescription UTF8String];
				FFGLLog::LogToHost( message.c_str() );
				loggedVisionFailure = true;
			}

			[handler release];
			[request release];
		}

		CVPixelBufferRelease( sourceBuffer );
		return success;
	}

	if( !loggedVisionUnavailable )
	{
		FFGLLog::LogToHost( "Apple Person Segmentation: Vision person segmentation requires macOS 12 or newer" );
		loggedVisionUnavailable = true;
	}
#endif

	return false;
}

void ApplePersonSegmentation::ReleaseMaskTexture()
{
	if( maskTexture != 0 )
	{
		glDeleteTextures( 1, &maskTexture );
		maskTexture = 0;
	}

	maskWidth = 0;
	maskHeight = 0;
	hasMask = false;
}
