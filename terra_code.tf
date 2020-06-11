provider "aws" {
  region = "ap-south-1" 
}

resource "aws_key_pair" "dep_key" {
  key_name = "rhskey"
  public_key = file("/terraform/test/pubkey.pem")
}


resource "aws_security_group" "rh-security-1" {
  name        = "rh-security-1"
  description = "Allow TLS inbound traffic"

  ingress {
    description = "TCP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    description = "Jenkins"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "RH-Security"
  }
}



resource "aws_instance" "rhel_apache_server" {
  ami = "ami-0155e924daafe6d06"
  instance_type = "t2.micro"
  key_name = "rhkey"
  availability_zone = "ap-south-1a"
  security_groups = ["rh-security-1"]

  tags = {
    Name = "Web-Server"
  }

  connection {
    type = "ssh"
    user = "ec2-user"
    private_key = file("/terraform/test/rhkey.pem")
    host = aws_instance.rhel_apache_server.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]
  }

}

resource "aws_ebs_volume" "rhel_ebs" {
  availability_zone = "ap-south-1a"
  size = 1

  tags = {
    Name = "RHEL_Volume"
  }
}

resource "aws_volume_attachment" "rhel_ebs_att" {
  device_name = "/dev/sdd"
  volume_id   = aws_ebs_volume.rhel_ebs.id
  instance_id = aws_instance.rhel_apache_server.id
  force_detach = true
}


resource "aws_s3_bucket" "rhel-s3-bucket01" {
  bucket = "rhel-s3-bucket01"
  acl    = "private"
  region = "ap-south-1"

  tags = {
    Name = "S3_Bucket"
  }
}

locals {
  s3_origin_id = "rh-s3-origin"
}

resource "aws_s3_bucket_object" "rhel-s3-bucket01" {
  bucket = "rhel-s3-bucket01"
  key    = "image.png"
  source = "/terraform/test/image.png"
}

resource "aws_s3_bucket_public_access_block" "s3_public" {
  bucket = "rhel-s3-bucket01"

  block_public_acls   = false
  block_public_policy = false
}

resource "aws_cloudfront_distribution" "cloudfront_dist" {
  origin {
    domain_name = aws_s3_bucket.rhel-s3-bucket01.bucket_regional_domain_name
    origin_id   = local.s3_origin_id

    custom_origin_config {
      http_port = 80
      https_port = 80
      origin_protocol_policy = "match-viewer"
      origin_ssl_protocols = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }
  
  enabled = true

  default_cache_behavior {
    allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl = 0
    default_ttl = 3600
    max_ttl = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

#Mounting the EBS volume
resource "null_resource" "mounting" {

  depends_on = [
    aws_volume_attachment.rhel_ebs_att,
  ]

  connection {
    type = "ssh"
    user = "ec2-user"
    private_key = file("/terraform/test/rhkey.pem")
    host = aws_instance.rhel_apache_server.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4 /dev/xvdd",
      "sudo mount /dev/xvdd /var/www/html",
      "sudo rm -rf /var/www/html",
      "sudo git clone https://github.com/Ninad07/AWS.git /var/www/html",
    ]
  }
}

resource "null_resource" "Testing" {

  depends_on = [
    null_resource.mounting,
  ]
  
  provisioner "local-exec" {
    command = "firefox ${aws_instance.rhel_apache_server.public_ip}"
  }
}


output "az" {
  value = aws_instance.rhel_apache_server.availability_zone
}

output "ip" {
  value = aws_instance.rhel_apache_server.public_ip
}

