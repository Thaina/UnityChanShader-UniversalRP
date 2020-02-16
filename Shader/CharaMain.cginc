// Upgrade NOTE: replaced '_Object2World' with 'unity_ObjectToWorld'
// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

// Character shader
// Includes falloff shadow and highlight, specular, reflection, and normal mapping

#define ENABLE_CAST_SHADOWS

// Material parameters
float4 _Color;
float4 _ShadowColor;

#ifdef ENABLE_SPECULAR
float _SpecularPower;
#endif

float4 _MainTex_ST;

float4 _MainLightPosition;
float4 _MainLightColor;

// Textures
sampler2D _MainTex;
sampler2D _FalloffSampler;
sampler2D _RimLightSampler;

#ifdef ENABLE_NORMAL_MAP
sampler2D _NormalMapSampler;
#endif

#ifdef ENABLE_SPECULAR
sampler2D _SpecularReflectionSampler;
sampler2D _EnvMapSampler;

#define FALLOFF_POWER 0.3
#else
#define FALLOFF_POWER 1.0
#endif

// Float types
#define float_t  half
#define float2_t half2
#define float3_t half3
#define float4_t half4

// Structure from vertex shader to fragment shader
struct v2f
{
	float4 pos      : SV_POSITION;
#ifdef ENABLE_CAST_SHADOWS
	LIGHTING_COORDS( 0, 1 )
	float2 uv       : TEXCOORD2;
	float3 eyeDir   : TEXCOORD3;
	float3 lightDir : TEXCOORD4;
	float3 normal   : TEXCOORD5;
	#ifdef ENABLE_NORMAL_MAP
		float3 tangent  : TEXCOORD6;
		float3 binormal : TEXCOORD7;
	#endif
#else
	float2 uv       : TEXCOORD0;
	float3 eyeDir   : TEXCOORD1;
	float3 lightDir : TEXCOORD2;
	float3 normal   : TEXCOORD3;
	#ifdef ENABLE_NORMAL_MAP
		float3 tangent  : TEXCOORD4;
		float3 binormal : TEXCOORD5;
	#endif
#endif
};


// Vertex shader
#ifdef ENABLE_SPECULAR
v2f vert( appdata_tan v )
#else
v2f vert( appdata_base v )
#endif
{
	v2f o;
	o.pos = UnityObjectToClipPos( v.vertex );
	o.uv = TRANSFORM_TEX( v.texcoord.xy, _MainTex );
	o.normal = normalize(mul(unity_ObjectToWorld,v.normal.xyz));

	// Eye direction vector
	float4 worldPos = mul( unity_ObjectToWorld, v.vertex );
	o.eyeDir = normalize( (_WorldSpaceCameraPos - worldPos).xyz );
	o.lightDir = WorldSpaceLightDir( v.vertex );

	#ifdef ENABLE_NORMAL_MAP
		// Binormal and tangent (for normal map)
		float4 tan = mul( unity_ObjectToWorld, float4_t( v.tangent.xyz, 1 ) );
		o.tangent = normalize( tan.xyz );
		o.binormal = normalize( cross( o.normal, o.tangent ) * v.tangent.w );
	#endif

	#ifdef ENABLE_CAST_SHADOWS
		TRANSFER_VERTEX_TO_FRAGMENT( o );
	#endif

	return o;
}

#ifdef ENABLE_SPECULAR
// Overlay blend
inline float3_t GetOverlayColor( float3_t inUpper, float3_t inLower )
{
	float3_t oneMinusLower = float3_t( 1.0, 1.0, 1.0 ) - inLower;
	float3_t valUnit = 2.0 * oneMinusLower;
	float3_t minValue = 2.0 * inLower - float3_t( 1.0, 1.0, 1.0 );
	float3_t greaterResult = inUpper * valUnit + minValue;

	float3_t lowerResult = 2.0 * inLower * inUpper;

	half3 lerpVals = round(inLower);
	return lerp(lowerResult, greaterResult, lerpVals);
}
#endif

fixed3 calculateAmbientLight(half3 normalWorld)
{
#ifndef TRI_COLOR_AMBIENT
	//Flat ambient is just the sky color
	return unity_AmbientSky.rgb;
#else
	//Magic constants used to tweak ambient to approximate pixel shader spherical harmonics
	fixed3 worldUp = fixed3(0,1,0);
	float skyGroundDotMul = 2.5;
	float minEquatorMix = 0.5;
	float equatorColorBlur = 0.33;

	float upDot = dot(normalWorld, worldUp);

	//Fade between a flat lerp from sky to ground and a 3 way lerp based on how bright the equator light is.
	//This simulates how directional lights get blurred using spherical harmonics

	//Work out color from ground and sky, ignoring equator
	float adjustedDot = upDot * skyGroundDotMul;
	fixed3 skyGroundColor = lerp(unity_AmbientGround, unity_AmbientSky, saturate((adjustedDot + 1.0) * 0.5));

	//Work out equator lights brightness
	float equatorBright = saturate(dot(unity_AmbientEquator.rgb, unity_AmbientEquator.rgb));

	//Blur equator color with sky and ground colors based on how bright it is.
	fixed3 equatorBlurredColor = lerp(unity_AmbientEquator, saturate(unity_AmbientEquator + unity_AmbientGround + unity_AmbientSky), equatorBright * equatorColorBlur);

	//Work out 3 way lerp inc equator light
	float smoothDot = pow(abs(upDot), 1);
	fixed3 equatorColor = lerp(equatorBlurredColor, unity_AmbientGround, smoothDot) * step(upDot, 0) + lerp(equatorBlurredColor, unity_AmbientSky, smoothDot) * step(0, upDot);

	return lerp(skyGroundColor, equatorColor, saturate(equatorBright + minEquatorMix));
#endif // TRI_COLOR_AMBIENT
}

	// Compute normal from normal map
	inline float3_t GetNormalFromMap( v2f input )
	{
#ifndef ENABLE_NORMAL_MAP
		return -normalize(input.normal);
#else
		float3_t normalVec = tex2D( _NormalMapSampler, input.uv ).xyz * 2 - 1;

		// Fix for Metal graphics API
		float3_t xBasis = float3_t( input.tangent.x, input.binormal.x, input.normal.x );
		float3_t yBasis = float3_t( input.tangent.y, input.binormal.y, input.normal.y );
		float3_t zBasis = float3_t( input.tangent.z, input.binormal.z, input.normal.z );

		normalVec = float3_t(
			dot( normalVec, xBasis ),
			dot( normalVec, yBasis ),
			dot( normalVec, zBasis )
		);

		return normalize(normalVec);
#endif
	}

// Fragment shader
float4 frag( v2f i ) : COLOR
{
	float4_t diffSamplerColor = tex2D( _MainTex, i.uv );

	float3_t normalVec = GetNormalFromMap( i );

	// Falloff. Convert the angle between the normal and the camera direction into a lookup for the gradient
	float3 viewDir = normalize(i.eyeDir);
	float3 lightDir = -normalize(_MainLightPosition.xyz);
	float_t normalDotEye = dot( normalVec, viewDir );
	float_t falloffU = clamp( 1 - abs( normalDotEye ), 0.02, 0.98 );
	float4_t falloffSamplerColor = FALLOFF_POWER * tex2D( _FalloffSampler, float2( falloffU, 0.25f ) );

	float3_t shadowColor = diffSamplerColor.rgb * diffSamplerColor.rgb;
	float3_t combinedColor = lerp( diffSamplerColor.rgb, shadowColor, falloffSamplerColor.r );
	combinedColor *= ( 1.0 + falloffSamplerColor.rgb * falloffSamplerColor.a );

	float3 sumlight = calculateAmbientLight(-normalVec);
	float nDotL = dot(normalVec,lightDir);
#ifdef ENABLE_SPECULAR
	// Specular
	float3 halfVec = normalize(lightDir + viewDir);
	float nDotH = dot(normalVec,halfVec);
	float4 lighting = lit( nDotL,nDotH,_SpecularPower );

	float4_t reflectionMaskColor = tex2D( _SpecularReflectionSampler, i.uv );
	sumlight += lighting.z * (_MainLightColor.rgb + reflectionMaskColor.rgb);

	// Reflection
	float3_t reflectVector = reflect( viewDir, normalVec );
	float2_t sphereMapCoords = 0.5 * ( float2_t( 1.0, 1.0 ) + reflectVector.xy );
	float3_t reflectColor = tex2D( _EnvMapSampler, sphereMapCoords ).rgb;
	reflectColor = GetOverlayColor( reflectColor, combinedColor );

	combinedColor = lerp( combinedColor, reflectColor, reflectionMaskColor.a );
#else
	float4 lighting = float4(0,saturate(nDotL),0,0);
#endif

	sumlight += _MainLightColor.rgb * lighting.y;
	combinedColor *= _Color.rgb * diffSamplerColor.rgb * sumlight;
	float opacity = diffSamplerColor.a * _Color.a;

#ifdef ENABLE_CAST_SHADOWS
	// Cast shadows
	float3_t castShadowColor = _ShadowColor.rgb * combinedColor;
	float_t attenuation = saturate( 2.0 * LIGHT_ATTENUATION( i ) - 1.0 );
	combinedColor = lerp( castShadowColor, combinedColor, attenuation );
#endif

	// Rimlight
	float_t rimlightDot = saturate( 0.5 * ( dot( normalVec, i.lightDir ) + 1.0 ) );
	falloffU = saturate( rimlightDot * falloffU );
	falloffU = tex2D( _RimLightSampler, float2( falloffU, 0.25f ) ).r;
	combinedColor = lerp(combinedColor,falloffU * diffSamplerColor.rgb,0.5);

	return float4( combinedColor, opacity );
}
