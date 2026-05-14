if( NOT APPLE )
	return()
endif()

enable_language( OBJCXX )

set(APPLE_MONOCULAR_DEPTH_SOURCES
	AppleMonocularDepth.h
	AppleMonocularDepth.mm
)

add_library(ffgl-plugin-apple-monocular-depth STATIC)
add_library(ffgl::plugin::apple_monocular_depth ALIAS ffgl-plugin-apple-monocular-depth)
target_sources(ffgl-plugin-apple-monocular-depth PRIVATE ${APPLE_MONOCULAR_DEPTH_SOURCES})
target_compile_definitions(ffgl-plugin-apple-monocular-depth PRIVATE GL_SILENCE_DEPRECATION)
target_link_libraries(ffgl-plugin-apple-monocular-depth PRIVATE
	ffgl::sdk
	"-framework CoreML"
	"-framework CoreVideo"
	"-framework Foundation"
	"-framework Vision"
	"-framework OpenGL"
)

add_library(AppleMonocularDepth MODULE
	${APPLE_MONOCULAR_DEPTH_SOURCES}
)
target_compile_definitions(AppleMonocularDepth PRIVATE GL_SILENCE_DEPRECATION)
target_link_libraries(AppleMonocularDepth PRIVATE
	ffgl::sdk
	"-framework CoreML"
	"-framework CoreVideo"
	"-framework Foundation"
	"-framework Vision"
	"-framework OpenGL"
)
set_target_properties(AppleMonocularDepth PROPERTIES
	BUNDLE TRUE
	BUNDLE_EXTENSION bundle
	PREFIX ""
	OUTPUT_NAME AppleMonocularDepth
	MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist.in"
)

function(embed_apple_monocular_depth_model MODEL_PATH DESTINATION_BASENAME)
	if( NOT MODEL_PATH OR NOT EXISTS "${MODEL_PATH}" )
		return()
	endif()

	get_filename_component(MODEL_EXTENSION "${MODEL_PATH}" EXT)
	if( NOT MODEL_EXTENSION )
		set(MODEL_EXTENSION ".mlmodelc")
	endif()

	add_custom_command(TARGET AppleMonocularDepth POST_BUILD
		COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_BUNDLE_CONTENT_DIR:AppleMonocularDepth>/Resources"
	)
	if( IS_DIRECTORY "${MODEL_PATH}" )
		add_custom_command(TARGET AppleMonocularDepth POST_BUILD
			COMMAND ${CMAKE_COMMAND} -E copy_directory "${MODEL_PATH}" "$<TARGET_BUNDLE_CONTENT_DIR:AppleMonocularDepth>/Resources/${DESTINATION_BASENAME}${MODEL_EXTENSION}"
		)
	else()
		add_custom_command(TARGET AppleMonocularDepth POST_BUILD
			COMMAND ${CMAKE_COMMAND} -E copy "${MODEL_PATH}" "$<TARGET_BUNDLE_CONTENT_DIR:AppleMonocularDepth>/Resources/${DESTINATION_BASENAME}${MODEL_EXTENSION}"
		)
	endif()
endfunction()

set(APPLE_MONOCULAR_DEPTH_FAST_MODEL "" CACHE PATH "Fast Core ML depth model to embed as DepthAnythingFast")
set(APPLE_MONOCULAR_DEPTH_QUALITY_MODEL "" CACHE PATH "Higher quality Core ML depth model to embed as DepthAnythingQuality")
set(APPLE_MONOCULAR_DEPTH_MODEL "" CACHE PATH "Legacy single Core ML depth model to embed as DepthAnything")

embed_apple_monocular_depth_model("${APPLE_MONOCULAR_DEPTH_FAST_MODEL}" "DepthAnythingFast")
embed_apple_monocular_depth_model("${APPLE_MONOCULAR_DEPTH_QUALITY_MODEL}" "DepthAnythingQuality")
if( APPLE_MONOCULAR_DEPTH_MODEL )
	embed_apple_monocular_depth_model("${APPLE_MONOCULAR_DEPTH_MODEL}" "DepthAnything")
endif()

install(
	TARGETS     ffgl-plugin-apple-monocular-depth AppleMonocularDepth
	EXPORT      ffgl--plugin-apple-monocular-depth-targets
	DESTINATION ${CMAKE_INSTALL_LIBDIR}
)
