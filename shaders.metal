#include <metal_stdlib>
using namespace metal;

struct rasterizer_data
{
	float4 position_ndc [[position]];
	float2 position;
	float2 center [[flat]];
};

constant float2 positions[] = {
        float2(0, 1),
        float2(0, 0),
        float2(1, 1),
        float2(1, 1),
        float2(1, 0),
        float2(0, 0),
};

vertex rasterizer_data
vertex_main(ushort vertex_id [[vertex_id]],
        uint instance_id [[instance_id]],
        constant float2 &offset,
        constant float2 &resolution,
        constant uint &column_count,
        constant float &diameter,
        constant float &padding)
{
	uint2 location = 0;
	location.x = instance_id % column_count;
	location.y = instance_id / column_count;

	float2 circle_position = (float2)location * (diameter + padding) + offset;

	float2 p0 = circle_position;
	float2 p1 = circle_position + diameter;

	p0 = floor(p0);
	p1 = ceil(p1);

	float2 vertex_position = p0 + (p1 - p0) * positions[vertex_id];

	float2 vertex_position_ndc = 2 * (vertex_position / resolution) - 1;

	rasterizer_data output = {};
	output.position_ndc = float4(vertex_position_ndc, 0, 1);
	output.position = vertex_position;
	output.center = circle_position + 0.5 * diameter;
	return output;
}

fragment float4
fragment_main(rasterizer_data input [[stage_in]], constant float &diameter, constant float4 &color)
{
	float radius = 0.5 * diameter;
	float distance_to_center = distance(input.center, input.position);

	float4 result = color;
	result.a = clamp(radius - distance_to_center + 0.5, 0.f, 1.f);
	result.xyz *= result.a;
	return result;
}
