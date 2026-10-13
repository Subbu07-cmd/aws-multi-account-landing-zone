output "vpc_id" { value = aws_vpc.this.id }
output "private_subnet_ids" { value = aws_subnet.private[*].id }
output "tgw_attachment_id" { value = try(aws_ec2_transit_gateway_vpc_attachment.this[0].id, null) }
