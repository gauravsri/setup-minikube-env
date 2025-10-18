# MongoDB on Kubernetes (Minikube)

Complete guide for deploying and managing MongoDB NoSQL database in your Minikube cluster.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Common Operations](#common-operations)
- [Database Management](#database-management)
- [User Management](#user-management)
- [Backup and Restore](#backup-and-restore)
- [Import and Export Data](#import-and-export-data)
- [Integration Examples](#integration-examples)
- [Troubleshooting](#troubleshooting)

## Overview

**MongoDB** is a popular NoSQL document database that stores data in flexible, JSON-like documents. This deployment provides:

- **Version**: MongoDB 8.0
- **Memory**: 512Mi request, 2Gi limit
- **CPU**: 250m request, 1000m limit
- **Storage**: 10Gi persistent volume
- **Port**: 27017 (NodePort: 30017)
- **Authentication**: Enabled by default

### Features

- ✅ Persistent storage with PVC
- ✅ Authentication and security enabled
- ✅ Optimized configuration for development
- ✅ Health checks (liveness and readiness probes)
- ✅ WiredTiger storage engine with compression
- ✅ Operation profiling for slow queries
- ✅ Comprehensive management scripts

## Quick Start

### Deploy MongoDB

```bash
# Deploy MongoDB to default namespace
./k8s/scripts/mongodb.sh deploy

# Or specify a namespace
NAMESPACE=myapp ./k8s/scripts/mongodb.sh deploy
```

### Check Status

```bash
./k8s/scripts/mongodb.sh status
```

### Access MongoDB Shell

```bash
# Open MongoDB Shell (mongosh)
./k8s/scripts/mongodb.sh mongosh

# Example commands in mongosh:
show dbs
use myapp
db.users.insertOne({name: "John", email: "john@example.com"})
db.users.find()
```

### Connection Information

```bash
# External (from host machine)
mongodb://admin:mongodb@<minikube-ip>:30017/admin

# Internal (from other pods in cluster)
mongodb://admin:mongodb@mongodb.default.svc.cluster.local:27017/admin

# Get Minikube IP
minikube ip
```

## Configuration

### Default Credentials

- **Username**: `admin`
- **Password**: `mongodb`
- **Database**: `admin`

**⚠️ Change credentials for production use!**

To change credentials, edit `k8s/manifests/mongodb.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mongodb-secret
type: Opaque
stringData:
  MONGO_INITDB_ROOT_USERNAME: "your-admin-user"
  MONGO_INITDB_ROOT_PASSWORD: "your-secure-password"
  MONGO_INITDB_DATABASE: "admin"
```

### Resource Allocation

Edit resource limits in `k8s/manifests/mongodb.yaml`:

```yaml
resources:
  requests:
    memory: "512Mi"   # Minimum guaranteed
    cpu: "250m"       # Minimum guaranteed
  limits:
    memory: "2Gi"     # Maximum allowed
    cpu: "1000m"      # Maximum allowed
```

### Storage Size

Modify PVC in `k8s/manifests/mongodb.yaml`:

```yaml
spec:
  resources:
    requests:
      storage: 10Gi   # Change to your desired size
```

### MongoDB Configuration

Key settings in `mongod.conf` (ConfigMap):

```yaml
storage:
  wiredTiger:
    engineConfig:
      cacheSizeGB: 1  # Adjust based on memory allocation

net:
  maxIncomingConnections: 100  # Adjust for load

operationProfiling:
  mode: slowOp
  slowOpThresholdMs: 100  # Log queries slower than 100ms
```

## Common Operations

### List All Commands

```bash
./k8s/scripts/mongodb.sh help
```

### Service Management

```bash
# Restart MongoDB
./k8s/scripts/mongodb.sh restart

# View logs (last 50 lines)
./k8s/scripts/mongodb.sh logs 50

# Follow logs in real-time
./k8s/scripts/mongodb.sh logs 50 true

# Show version
./k8s/scripts/mongodb.sh version

# Show server statistics
./k8s/scripts/mongodb.sh stats

# Remove MongoDB
./k8s/scripts/mongodb.sh remove
```

## Database Management

### List Databases

```bash
./k8s/scripts/mongodb.sh list-db
```

### Create Database

```bash
# MongoDB creates databases on first write
./k8s/scripts/mongodb.sh create-db myapp
```

This creates a database with an initial collection. MongoDB will fully create the database when you insert your first document.

### List Collections

```bash
# List collections in a database
./k8s/scripts/mongodb.sh list-collections myapp
```

### Execute MongoDB Commands

```bash
# Execute a command
./k8s/scripts/mongodb.sh eval "db.users.find()" myapp

# More examples
./k8s/scripts/mongodb.sh eval "db.stats()" myapp
./k8s/scripts/mongodb.sh eval "db.users.countDocuments({})" myapp
```

## User Management

### Create User

```bash
# Create user with readWrite role (default)
./k8s/scripts/mongodb.sh create-user appuser mypassword myapp readWrite

# Create user with read-only access
./k8s/scripts/mongodb.sh create-user reader mypassword myapp read

# Create user with admin privileges
./k8s/scripts/mongodb.sh create-user dbadmin mypassword myapp dbAdmin
```

### Grant Additional Roles

```bash
# Grant dbAdmin role to existing user
./k8s/scripts/mongodb.sh grant appuser myapp dbAdmin

# Grant readWrite on another database
./k8s/scripts/mongodb.sh grant appuser otherdb readWrite
```

### Common MongoDB Roles

| Role | Permissions |
|------|------------|
| `read` | Read data from database |
| `readWrite` | Read and write data |
| `dbAdmin` | Database administration tasks |
| `userAdmin` | Create and modify users |
| `dbOwner` | Full privileges on database |
| `root` | Full system-wide privileges |

## Backup and Restore

### Backup Database

```bash
# Backup specific database
./k8s/scripts/mongodb.sh backup myapp ./backups

# Backup all databases (backup admin database)
./k8s/scripts/mongodb.sh backup admin ./backups

# Backup with timestamp
./k8s/scripts/mongodb.sh backup myapp ./backups/backup-$(date +%Y%m%d-%H%M%S)
```

This creates a compressed archive: `./backups/myapp.archive.gz`

### Restore Database

```bash
# Restore from backup
./k8s/scripts/mongodb.sh restore ./backups/myapp.archive.gz myapp

# Restore to different database
./k8s/scripts/mongodb.sh restore ./backups/prod.archive.gz dev_copy
```

### Automated Backup Script

Create a backup script for regular backups:

```bash
#!/bin/bash
# mongodb-backup.sh

NAMESPACE=myapp
BACKUP_DIR="/backups/mongodb"
DATE=$(date +%Y%m%d-%H%M%S)

# Create backup
NAMESPACE=$NAMESPACE ./k8s/scripts/mongodb.sh backup myapp "$BACKUP_DIR/$DATE"

# Keep only last 7 days
find "$BACKUP_DIR" -name "*.archive.gz" -mtime +7 -delete

echo "Backup completed: $BACKUP_DIR/$DATE/myapp.archive.gz"
```

## Import and Export Data

### Export Collection to JSON

```bash
# Export collection
./k8s/scripts/mongodb.sh export myapp users users.json

# Export with timestamp
./k8s/scripts/mongodb.sh export myapp users users-$(date +%Y%m%d).json
```

### Import JSON Data

```bash
# Import JSON array
./k8s/scripts/mongodb.sh import data.json myapp users
```

**Example JSON file** (`data.json`):

```json
[
  {
    "name": "Alice",
    "email": "alice@example.com",
    "age": 30
  },
  {
    "name": "Bob",
    "email": "bob@example.com",
    "age": 25
  }
]
```

### Large Data Import

For large datasets, copy data into the pod and use `mongoimport` directly:

```bash
# Get pod name
POD=$(kubectl get pods -l app=mongodb -n myapp -o jsonpath='{.items[0].metadata.name}')

# Copy file to pod
kubectl cp large-data.json myapp/$POD:/tmp/data.json

# Import data
kubectl exec -n myapp $POD -- mongoimport \
  -u admin -p mongodb --authenticationDatabase admin \
  --db myapp --collection large_collection \
  --file /tmp/data.json --jsonArray
```

## Integration Examples

### Java (Spring Boot)

**Maven Dependency:**

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-data-mongodb</artifactId>
</dependency>
```

**application.yml:**

```yaml
spring:
  data:
    mongodb:
      # External access from host
      uri: mongodb://admin:mongodb@<minikube-ip>:30017/myapp?authSource=admin

      # Or from within cluster
      # uri: mongodb://admin:mongodb@mongodb.default.svc.cluster.local:27017/myapp?authSource=admin
```

**Entity Example:**

```java
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;
import lombok.Data;

@Data
@Document(collection = "users")
public class User {
    @Id
    private String id;
    private String name;
    private String email;
    private Integer age;
}
```

**Repository:**

```java
import org.springframework.data.mongodb.repository.MongoRepository;

public interface UserRepository extends MongoRepository<User, String> {
    Optional<User> findByEmail(String email);
    List<User> findByAgeGreaterThan(int age);
}
```

### Python (PyMongo)

**Install:**

```bash
pip install pymongo
```

**Connection:**

```python
from pymongo import MongoClient
import os

# Get Minikube IP
minikube_ip = os.popen('minikube ip').read().strip()

# Connect
client = MongoClient(f'mongodb://admin:mongodb@{minikube_ip}:30017/admin')

# Or from within cluster
# client = MongoClient('mongodb://admin:mongodb@mongodb.default.svc.cluster.local:27017/admin')

# Access database
db = client.myapp

# Insert document
db.users.insert_one({
    "name": "Alice",
    "email": "alice@example.com",
    "age": 30
})

# Find documents
for user in db.users.find({"age": {"$gte": 25}}):
    print(user)
```

### Node.js

**Install:**

```bash
npm install mongodb
```

**Connection:**

```javascript
const { MongoClient } = require('mongodb');

// Get connection string
const uri = 'mongodb://admin:mongodb@<minikube-ip>:30017/myapp?authSource=admin';

async function main() {
    const client = new MongoClient(uri);

    try {
        await client.connect();
        const db = client.db('myapp');

        // Insert document
        await db.collection('users').insertOne({
            name: 'Alice',
            email: 'alice@example.com',
            age: 30
        });

        // Find documents
        const users = await db.collection('users').find({ age: { $gte: 25 } }).toArray();
        console.log(users);
    } finally {
        await client.close();
    }
}

main().catch(console.error);
```

### Go

**Install:**

```bash
go get go.mongodb.org/mongo-driver/mongo
```

**Connection:**

```go
package main

import (
    "context"
    "fmt"
    "log"
    "time"

    "go.mongodb.org/mongo-driver/bson"
    "go.mongodb.org/mongo-driver/mongo"
    "go.mongodb.org/mongo-driver/mongo/options"
)

type User struct {
    Name  string `bson:"name"`
    Email string `bson:"email"`
    Age   int    `bson:"age"`
}

func main() {
    ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
    defer cancel()

    client, err := mongo.Connect(ctx, options.Client().
        ApplyURI("mongodb://admin:mongodb@<minikube-ip>:30017/myapp?authSource=admin"))
    if err != nil {
        log.Fatal(err)
    }
    defer client.Disconnect(ctx)

    collection := client.Database("myapp").Collection("users")

    // Insert
    user := User{Name: "Alice", Email: "alice@example.com", Age: 30}
    _, err = collection.InsertOne(ctx, user)
    if err != nil {
        log.Fatal(err)
    }

    // Find
    var result User
    err = collection.FindOne(ctx, bson.M{"email": "alice@example.com"}).Decode(&result)
    if err != nil {
        log.Fatal(err)
    }
    fmt.Printf("%+v\n", result)
}
```

## Troubleshooting

### MongoDB Pod Not Starting

```bash
# Check pod status
kubectl get pods -l app=mongodb -n <namespace>

# Describe pod for events
kubectl describe pod <mongodb-pod> -n <namespace>

# Check logs
./k8s/scripts/mongodb.sh logs 100
```

**Common issues:**

- **Insufficient resources**: Increase memory/CPU limits
- **PVC binding issues**: Check if PVC is bound: `kubectl get pvc -n <namespace>`
- **Image pull errors**: Check network connectivity

### Connection Refused

```bash
# Check if service is running
./k8s/scripts/mongodb.sh status

# Verify NodePort
kubectl get svc mongodb -n <namespace>

# Get Minikube IP
minikube ip

# Test connection
telnet $(minikube ip) 30017
```

### Authentication Failed

Make sure to use the correct credentials and authentication database:

```bash
# Correct format
mongodb://admin:mongodb@<host>:30017/<database>?authSource=admin

# The authSource must be 'admin' for the root user
```

### Out of Memory

If MongoDB crashes due to OOM:

```bash
# Increase memory limits in manifest
kubectl edit statefulset mongodb -n <namespace>

# Or edit the YAML file and re-apply
vim k8s/manifests/mongodb.yaml
kubectl apply -f k8s/manifests/mongodb.yaml -n <namespace>
```

### Slow Queries

```bash
# Check slow query log
./k8s/scripts/mongodb.sh eval "db.system.profile.find().limit(10).sort({ts:-1})"

# Show current operations
./k8s/scripts/mongodb.sh eval "db.currentOp()"

# Create index to improve performance
./k8s/scripts/mongodb.sh eval "db.users.createIndex({email: 1})" myapp
```

### Data Persistence

If data is lost after pod restart:

```bash
# Check PVC status
kubectl get pvc mongodb-pvc -n <namespace>

# Verify mount
kubectl describe pod <mongodb-pod> -n <namespace> | grep -A5 Mounts
```

### Reset MongoDB

```bash
# Remove MongoDB (keeps PVC)
./k8s/scripts/mongodb.sh remove

# Delete PVC to start fresh
kubectl delete pvc mongodb-pvc -n <namespace>

# Deploy again
./k8s/scripts/mongodb.sh deploy
```

## Best Practices

### 1. Security

- ✅ Change default credentials
- ✅ Use specific database users (not root)
- ✅ Enable TLS/SSL for production
- ✅ Use Kubernetes secrets for credentials
- ✅ Implement network policies

### 2. Performance

- ✅ Create indexes for frequently queried fields
- ✅ Monitor slow queries (profiling)
- ✅ Adjust WiredTiger cache size based on memory
- ✅ Use projection to limit returned fields
- ✅ Consider sharding for large datasets

### 3. Backup Strategy

- ✅ Regular automated backups
- ✅ Test restore procedures
- ✅ Store backups off-cluster
- ✅ Implement backup retention policy

### 4. Monitoring

```bash
# Monitor resource usage
kubectl top pod -l app=mongodb -n <namespace>

# Check database stats
./k8s/scripts/mongodb.sh eval "db.stats()" myapp

# Monitor connections
./k8s/scripts/mongodb.sh eval "db.serverStatus().connections"
```

## Additional Resources

- [MongoDB Documentation](https://docs.mongodb.com/)
- [MongoDB Shell (mongosh)](https://docs.mongodb.com/mongodb-shell/)
- [MongoDB Drivers](https://docs.mongodb.com/drivers/)
- [MongoDB University](https://university.mongodb.com/) - Free courses
- [Kubernetes StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)

## Support

For issues or questions:
- Check logs: `./k8s/scripts/mongodb.sh logs`
- Review status: `./k8s/scripts/mongodb.sh status`
- See main README: [../README.md](../README.md)
