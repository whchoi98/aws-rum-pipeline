# terraform/modules/openreplay/elasticache.tf
# ElastiCache Redis 7.1 (OpenReplay 캐시/세션 스토어)

resource "aws_elasticache_subnet_group" "openreplay" {
  name       = "${var.project_name}-openreplay-redis"
  subnet_ids = var.private_subnet_ids

  tags = merge(var.tags, { Name = "${var.project_name}-openreplay-redis-subnet" })
}

# Redis 보안 그룹 — EC2 SG에서만 6379 인바운드 허용
resource "aws_security_group" "redis" {
  name_prefix = "${var.project_name}-or-redis-"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
    description     = "Redis from EC2 only"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.project_name}-or-redis-sg" })
}

# ElastiCache Redis 클러스터 (단일 노드)
resource "aws_elasticache_cluster" "openreplay" {
  cluster_id      = "${var.project_name}-or-redis"
  engine          = "redis"
  engine_version  = "7.1"
  node_type       = "cache.t4g.micro"
  num_cache_nodes = 1

  subnet_group_name  = aws_elasticache_subnet_group.openreplay.name
  security_group_ids = [aws_security_group.redis.id]

  tags = merge(var.tags, { Name = "${var.project_name}-openreplay-redis" })
}
