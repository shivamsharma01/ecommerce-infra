#!/bin/bash

# Array of your microservice folder names (Replace these with your actual folder names)
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

# Get the total number of services to handle the delay logic correctly
TOTAL_SERVICES=${#SERVICES[@]}

for i in "${!SERVICES[@]}"; do
    SERVICE="${SERVICES[$i]}"
    
    if [ -d "$SERVICE" ]; then
        echo "🚀 Starting $SERVICE in a new terminal tab..."
        
        # Opens a new Ubuntu terminal tab, navigates to the folder, and boots the microservice
        gnome-terminal --tab --title="$SERVICE" -- bash -c "cd '$(pwd)/$SERVICE' && ./gradlew bootRun --args='--spring.profiles.active=local'; exec bash"
        
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
        echo "⚠️ Directory $SERVICE not found, skipping."
    fi
done

echo "✅ All services have been triggered!"

