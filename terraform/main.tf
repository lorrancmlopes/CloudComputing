# Cria uma instância de banco de dados do Amazon RDS
resource "aws_db_instance" "example" {
  engine                = "mysql"
  identifier            = "mysqlforlambdaterraform"
  allocated_storage     = 5
  max_allocated_storage = 100
  instance_class        = "db.t2.micro"
  publicly_accessible   = false

  db_name             = "ExampleDB"
  username            = "admin"
  password            = "senhaDoBancoDeDados"
  skip_final_snapshot = true

  vpc_security_group_ids = [aws_default_security_group.default.id]
}

# Cria um perfil de execução de função
resource "aws_iam_role" "role" {
  name = "lambda-vpc-sqs-role-terraform"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# Cria uma policy 
resource "aws_iam_policy" "policy" {
  name = "necessary-policy"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "VisualEditor0",
        "Effect" : "Allow",
        "Action" : [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:SendMessage",
          "sqs:GetQueueUrl"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Resource" : "arn:aws:logs:*:*:*"
      }
    ]
  })
}


#associamos a policy à função IAM
resource "aws_iam_role_policy_attachment" "example" {
  policy_arn = aws_iam_policy.policy.arn
  role       = aws_iam_role.role.name
}

resource "local_file" "python_script" {
  filename = "./source_lambda/lambda_function.py"
  content  = <<-EOF
import sys
import logging
import pymysql
import json

# rds settings
rds_host  = "${aws_db_instance.example.endpoint}"[:-5]
user_name = "admin"
password  = "senhaDoBancoDeDados"
db_name   = "ExampleDB"

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# create the database connection outside of the handler to allow connections to be
# re-used by subsequent function invocations.
try:
    conn = pymysql.connect(host=rds_host, user=user_name, passwd=password, db=db_name, connect_timeout=5)
except pymysql.MySQLError as e:
    logger.error("ERROR: Unexpected error: Could not connect to MySQL instance.")
    logger.error(e)
    sys.exit()

logger.info("SUCCESS: Connection to RDS MySQL instance succeeded")

def lambda_handler(event, context):
    """
    This function creates a new RDS database table and writes records to it
    """
    message = event['Records'][0]['body']
    data = json.loads(message)
    CustID = data['CustID']
    Name = data['Name']

    item_count = 0
    sql_string = f"insert into Customer (CustID, Name) values({CustID}, '{Name}')"

    with conn.cursor() as cur:
        cur.execute("create table if not exists Customer ( CustID  int NOT NULL, Name varchar(255) NOT NULL, PRIMARY KEY (CustID))")
        cur.execute(sql_string)
        conn.commit()
        cur.execute("select * from Customer")
        logger.info("The following items have been added to the database:")
        for row in cur:
            item_count += 1
            logger.info(row)
    conn.commit()

    return "Added %d items to RDS MySQL table" %(item_count)
EOF
}

data "archive_file" "lambda_archive" {
  depends_on  = [local_file.python_script]
  source_dir  = "./source_lambda"
  output_path = "lambda_function.zip"
  type        = "zip"
}

# Cria a função Lambda
resource "aws_lambda_function" "test_lambda" {
  filename      = "lambda_function.zip"
  function_name = "LambdaFunctionWithRDS-terraform"
  role          = aws_iam_role.role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"

  vpc_config {
    subnet_ids         = aws_default_subnet.default[*].id
    security_group_ids = [aws_default_security_group.default.id]
  }

  depends_on = [ data.archive_file.lambda_archive ]
}

resource "aws_default_subnet" "default" {
  count             = 6
  availability_zone = element(["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d", "us-east-1e", "us-east-1f"], count.index)

}

resource "aws_default_security_group" "default" {
  vpc_id = aws_default_vpc.default.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

resource "aws_default_vpc" "default" {
}

# Cria uma fila do Amazon SQS
resource "aws_sqs_queue" "my_queue" {
  name = "LambdaRDSQueue"
}

# Cria um mapeamento da origem do evento para invocar sua função do Lambda
resource "aws_lambda_event_source_mapping" "resource_queue" {
  event_source_arn = aws_sqs_queue.my_queue.arn
  function_name    = aws_lambda_function.test_lambda.function_name
  batch_size       = 1
}