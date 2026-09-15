#!/bin/bash

# Fixed array structure (separated by spaces, not commas)
SERVICES=(
    "ecommerce-auth"
    "ecommerce-user"
    "ecommerce-email"
    "ecommerce-product"
    "ecommerce-product-indexing"
    "ecommerce-search"
    "ecommerce-inventory"
    "ecommerce-cart"
    "ecommerce-order"
    "ecommerce-payment"
)

TOTAL_SERVICES=${#SERVICES[@]}

for i in "${!SERVICES[@]}"; do
    SERVICE="${SERVICES[$i]}"
    
    if [ -d "$SERVICE" ]; then
        
        # FIX FOR THE ^M ERROR: Automatically convert Windows CRLF line endings to Linux LF
        if [ -f "$SERVICE/gradlew" ]; then
            sed -i -e 's/\r$//' "$SERVICE/gradlew"
            chmod +x "$SERVICE/gradlew"  # Ensure it has execute permissions
        fi
        
        # 🔀 CONDITIONAL ROUTING: Choose the right command based on the service name
        if [ "$SERVICE" == "ecommerce-search" ]; then
            echo "🚀 Starting $SERVICE using plain bootRun..."
            CMD="./gradlew bootRun"
        else
            echo "🚀 Starting $SERVICE with local profile..."
            CMD="./gradlew bootRun --args='--spring.profiles.active=local'"
        fi
        
        # Opens a new Ubuntu terminal tab, navigates to the folder, and boots the microservice
        gnome-terminal --tab --title="$SERVICE" -- bash -c "cd '$(pwd)/$SERVICE' && $CMD; exec bash"
        
        # Only wait if this is NOT the last service in the list
        if [ $((i + 1)) -lt $TOTAL_SERVICES ]; then
            echo "⏳ Waiting 60 seconds before starting the next service..."
            
            # Simple countdown timer visual
            for sec in {60..1}; do
                printf "\rNext service starts in %02d seconds... " "$sec"
                sleep 1
            done
            echo -e "\n" # Move to a clean line
        fi
    else
        echo "⚠️ Directory '$SERVICE' not found, skipping."
    fi
done

echo "✅ All services have been triggered!"
