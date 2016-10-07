//Required for printf()
#include <stdio.h>
//Required for pow(), sqrt()
#include <math.h>

//Represents a point on a
//Euclidean Grid
typedef struct {
	int x;
	int y;
	char zone;

} Point;

// Thread block size
#define BLOCK_SIZE 16

//Prototype for the createVoronoi function.
__global__ void createVoronoi(Point *l_points, int gridWidth, int gridHeight,
		char *l_result, int numPoints);

/*
 * Copies the result array from the GPU after the zone points are calculated.
 * Copies points to the GPU. The kernel finds the Zones in parallel.
 */
void getVoronoiArray(char *result, int gridHeight, int gridWidth, Point *points,
		int numPoints) {

	//Create pointer to char array to hold Zone results
	//Allocate pointer in GPU shared memory
	char *l_result;
	size_t size = (gridWidth * gridHeight) * pow(BLOCK_SIZE, 2) * sizeof(char);
	cudaError_t err = cudaMalloc(&l_result, size);
	printf("CUDA malloc result array: %s\n", cudaGetErrorString(err));

	//Create Point pointer to pass points to GPU shared memory
	Point *l_points;
	err = cudaMalloc((void**) &l_points, sizeof(Point) * numPoints);
	printf("CUDA malloc Points: %s\n", cudaGetErrorString(err));
	err = cudaMemcpy(l_points, points, sizeof(Point) * numPoints,
			cudaMemcpyHostToDevice);
	printf("Copy Points to GPU: %s\n", cudaGetErrorString(err));


	// Invoke kernel
	dim3 dimBlock(BLOCK_SIZE, BLOCK_SIZE);
	dim3 dimGrid(gridWidth, gridHeight);
	createVoronoi<<<dimGrid, dimBlock>>>(l_points, gridWidth, gridHeight, l_result, numPoints);
	err = cudaThreadSynchronize();
	printf("Run kernel: %s\n", cudaGetErrorString(err));

	// Read the diagram from GPU into host memory
	err = cudaMemcpy(result, l_result, size, cudaMemcpyDeviceToHost);
	printf("Copy result from device: %s\n", cudaGetErrorString(err));

	// Free device memory
	cudaFree(l_result);
	cudaFree(l_points);
}

/*
 * Finds the Zone for each thread run. The coordinate generated is based
 * on the (x,y) of the Block, and (x,y) for each thread.
 */
__device__ char getZone(Point *l_points, int x, int y, int numPoints) {
	//Find the first point
	double smallest = sqrt(
			pow((double) l_points[0].x - x, 2)
					+ pow((double) l_points[0].y - y, 2));
	char zone = l_points[0].zone;
	double dist_temp = 0;

	//For each point
	for (int i = 1; i < numPoints; i++) {

		//Find distance to current point
		dist_temp = sqrt(
				pow((double) l_points[i].x - x, 2)
						+ pow((double) l_points[i].y - y, 2));

		//If Point distance is closer,
		//Change the Zone value.
		if (dist_temp < smallest) {
			smallest = dist_temp;
			zone = l_points[i].zone;
		}
	}

	return zone;
}

/*
 *Determines the coordinate of each point in the plane.
 *Sets the result array equal to the appropriate Zone id.
 *Runs in parallel.
 */
__global__ void createVoronoi(Point *l_points, int gridWidth, int gridHeight,
		char *l_result, int numPoints) {

	// X,Y Coordinate of the Block in the defined grid
	int blockCol = blockIdx.x;
	int blockrow = blockIdx.y;

	//X,Y Coordinate of threads in each block
	int row = threadIdx.y;
	int col = threadIdx.x;

	//Find the (x,y) point of the current value
	int x = (blockCol * BLOCK_SIZE) + col;
	int y = (blockrow * BLOCK_SIZE) + row;

	__syncthreads();

	//Set the result array to the proper zone
	l_result[(y * (BLOCK_SIZE * gridWidth)) + x] = getZone(l_points, x, y, numPoints);

}

/*
 * The main method of the program.
 * The program takes the following parameters:
 *
 * int-height int-width int-x1 int-y1 char-y2 xn...
 *
 * Height and width define the result array
 * properties, and (x1,y1) define a Euclidean
 * point, and z1 defines a Zone, which in this
 * case is a single char.
 *
 */
int main(int argc, char* argv[]) {

	//If less than 6, Not enough params to run
	if (argc < 6) {
		printf(
			"Voronoi height, width, x1,y1,z1,x2,y2,z2 ...\nWhere height, width, x, and y are ints\nand z is a single char.");
		return 1;
	}

	//If point params mod 3 does not equal 1
	//There is an unfinished point
	if ((argc - 3) % 3 != 0) {
		printf(
			"Voronoi height, width, x1,y1,z1,x2,y2,z2 ...\nWhere height, width, x, and y are ints\nand z is a single char.");
		return 1;
	}

	//Read height/width of result
	int height = atoi(argv[1]);
	int width = atoi(argv[2]);

	//The total number of points
	int numPoints = (argc - 3) / 3;

	//Create memory allocation for points
	Point * points;
	points = (Point*) malloc(numPoints * sizeof(Point));

	//Read in the point values
	int start = 3;
	for (int i = 0; i < numPoints; i++) {
		points[i].x = atoi(argv[start++]);
		points[i].y = atoi(argv[start++]);
		points[i].zone = argv[start++][0];
	}

	//Grid width - how long the cuda grid must be to obtain result
	int gridWidth = (width / BLOCK_SIZE) + 1;
	//Grid Width - how high the cuda grid must be to obtain result
	int gridHeight = (height / BLOCK_SIZE) + 1;

	//Allocate memory to hold result ( char array )
	char *result;
	result = (char*) malloc(
			(gridWidth * gridHeight) * pow(BLOCK_SIZE, 2) * sizeof(char));

	//Writes the array of zones to the result array
	getVoronoiArray(result, gridHeight, gridWidth, points, numPoints);

	//Shows success!
	printf("Success\n\n");

	//Some information for the user
	printf("Height:%d, Width:%d\n\n", height, width);

	//Prints the values. The lower left is the origin at (0,0).
	int print_width = (BLOCK_SIZE * gridWidth) - width;

	for (int i = height; i > 0; i--) {

		for (int j = gridWidth * BLOCK_SIZE; j > print_width; j--)
			printf("%c ", result[i * (gridWidth * BLOCK_SIZE) - j]);
		printf("\n");
	}

	//Success
	return 1;
}
