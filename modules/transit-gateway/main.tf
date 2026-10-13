resource "aws_ec2_transit_gateway" "this" {
  description                     = "Org hub transit gateway"
  amazon_side_asn                 = var.asn
  auto_accept_shared_attachments  = "enable"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  dns_support                     = "enable"
  tags                            = merge(var.tags, { Name = "org-tgw" })
}

resource "aws_ram_resource_share" "tgw" {
  name                      = "org-transit-gateway"
  allow_external_principals = false
  tags                      = var.tags
}

resource "aws_ram_resource_association" "tgw" {
  resource_arn       = aws_ec2_transit_gateway.this.arn
  resource_share_arn = aws_ram_resource_share.tgw.arn
}

resource "aws_ram_principal_association" "org" {
  principal          = var.organization_arn
  resource_share_arn = aws_ram_resource_share.tgw.arn
}

# Segmented routing: prod and nonprod can reach shared services, never each other.
resource "aws_ec2_transit_gateway_route_table" "segment" {
  for_each           = toset(["shared", "prod", "nonprod"])
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  tags               = merge(var.tags, { Name = "tgw-rt-${each.key}" })
}

resource "aws_ec2_transit_gateway_route" "to_egress" {
  for_each                       = toset(["prod", "nonprod"])
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = var.egress_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.segment[each.key].id
}
