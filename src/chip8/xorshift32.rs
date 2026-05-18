pub struct Rng
{
	state: u32,
}

impl Rng
{
	#[inline]
	pub const fn new(seed: u32) -> Self
	{
		Self { state: seed }
	}

	#[inline]
	pub fn next_u32(&mut self) -> u32
	{
		let mut x = self.state;

		x ^= x << 13;
		x ^= x >> 17;
		x ^= x << 5;

		self.state = x;
		x
	}

	#[inline]
	pub fn next_u8(&mut self) -> u8
	{
		self.next_u32() as u8
	}
}
