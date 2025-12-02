# Use the official Node.js LTS image.  Alpine reduces image size.
FROM node:18-alpine AS base

# Create app directory
WORKDIR /app

# Install app dependencies
# Copy package.json and package-lock.json before copying other files.
COPY package.json ./
COPY package-lock.json* ./

# Install only production dependencies
RUN npm install --production

# Copy application source
COPY src ./src

# Expose the port the app listens on
EXPOSE 3000

# Define the default command to run the app
CMD ["npm", "start"]