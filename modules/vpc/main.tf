# AZs are pinned explicitly (CKV_AWS_394) so the subnet layout never shifts when AWS adds a zone.
locals {
  azs = var.azs
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(var.tags, { Name = var.name })
}

resource "aws_subnet" "private" {
  count             = 3
  vpc_id            = aws_vpc.this.id
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(var.cidr, 4, count.index)
  tags              = merge(var.tags, { Name = "${var.name}-private-${local.azs[count.index]}", Tier = "private" })
}

resource "aws_subnet" "tgw" {
  count             = 3
  vpc_id            = aws_vpc.this.id
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(var.cidr, 12, 4000 + count.index)
  tags              = merge(var.tags, { Name = "${var.name}-tgw-${local.azs[count.index]}", Tier = "tgw" })
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-private" })
}

resource "aws_route_table_association" "private" {
  count          = 3
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  count              = var.transit_gateway_id == null ? 0 : 1
  transit_gateway_id = var.transit_gateway_id
  vpc_id             = aws_vpc.this.id
  subnet_ids         = aws_subnet.tgw[*].id
  tags               = merge(var.tags, { Name = var.name, Segment = var.segment })

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false
}

resource "aws_route" "default_via_tgw" {
  count                  = var.transit_gateway_id == null ? 0 : 1
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = var.transit_gateway_id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.this]
}

resource "aws_flow_log" "this" {
  vpc_id               = aws_vpc.this.id
  traffic_type         = "ALL"
  log_destination_type = "s3"
  log_destination      = var.flow_log_bucket_arn
  tags                 = var.tags
}

resource "aws_default_security_group" "lockdown" {
  vpc_id = aws_vpc.this.id
}
