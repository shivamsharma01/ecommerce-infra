#!/bin/bash

echo "Stopping all active Spring Boot microservices..."

# Finds and gracefully terminates the processes running the 'bootRun' command
pkill -f "bootRun"

echo "✅ All services stopped successfully!"

