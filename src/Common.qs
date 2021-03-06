namespace Qram{
    open Microsoft.Quantum.Intrinsic;
    open Microsoft.Quantum.Canon;
    open Microsoft.Quantum.Logical;
    open Microsoft.Quantum.Arrays;
    open Microsoft.Quantum.Math;
    open Microsoft.Quantum.Arithmetic;

    /// # Summary
    /// Type representing a generic QROM type.
    /// # Input
    /// ## Read
    /// The named operation that will look up data from the QROM.
    /// ## AddressSize
    /// The size (number of bits) needed to represent an address for the QROM.
    /// ## DataSize
    /// The size (number of bits) needed to represent a data value for the QROM.
    newtype QROM = (
        Read : ((LittleEndian, Qubit[]) => Unit is Adj + Ctl), 
        AddressSize : Int,
        DataSize : Int
    );

    /// # Summary
    /// Type representing a generic QRAM type.
    /// # Input
    /// ## Read
    /// Takes an address, memory, and target qubit to perform the lookup.
    /// ## Write
    /// Writes a data value at address Int, with the value Bool[] to a MemoryRegister.
    /// ## AddressSize
    /// The size (number of bits) needed to represent an address for the QRAM.
    /// ## DataSize
    /// The size (number of bits) needed to represent a data value for the QRAM.
    newtype QRAM = (
        Read : ((AddressRegister, MemoryRegister, Qubit[]) => Unit is Adj + Ctl), 
        Write : ((MemoryRegister, MemoryCell) => Unit), 
        AddressSize : Int,
        DataSize : Int
    );

    /// # Summary
    /// Wrapper for registers that represent a quantum memory.
    newtype MemoryRegister = (Qubit[]);

    /// # Summary
    /// Wrapper for registers that represent addresses.
    newtype AddressRegister = (Qubit[]);

    /// # Summary
    /// Describes a single data point in a memory.
    /// # Input
    /// ## Address
    /// The address in the memory that the MemoryCell describes.
    /// ## Value
    /// The value in the memory that the MemoryCell describes.
    newtype MemoryCell = (Address : Int, Value : Bool[]);

    /// # Summary
    /// Describes a dataset as well as metadata about the data.
    /// # Input
    /// ## DataSet
    /// The data explicitly stored in the memory.
    /// ## AddressSize
    /// The number of bits required to represent the largest explicit address
    /// in the DataSet.
    /// ## DataSize
    /// The number of bits required to represent the largest data valueS
    /// in the DataSet.
    newtype MemoryBank = (DataSet : MemoryCell[], AddressSize : Int, DataSize : Int);

    /// # Summary
    /// Helper function that returns the address of a particular MemoryCell.
    /// Basically a lambda function for the unwrapping.
    /// # Input
    /// ## cell
    /// The memory cell you want to know about.
    /// # Output
    /// The address of that MemoryCell.
    function AddressLookup(cell : MemoryCell) : Int {
        return cell::Address;
    }

    /// # Summary
    /// Helper function that returns the Value of a particular MemoryCell.
    /// Basically a lambda function for the unwrapping.
    /// # Input
    /// ## cell
    /// The memory cell you want to know about.
    /// # Output
    /// The Value of that MemoryCell.
    function ValueLookup(cell : MemoryCell) : Bool[] {
        return cell::Value;
    }

    /// # Summary
    /// Easy way to get all of the addresses specified in a MemoryBank.
    /// # Input
    /// ## bank
    /// The MemoryBank you want to know about.
    /// # Output
    /// A list of addresses given by each MemoryCell in the DataSet.
    function AddressList(bank : MemoryBank) : Int[] {
        return Mapped(AddressLookup, bank::DataSet);
    }

    /// # Summary
    /// Easy way to get all of the values specified in a MemoryBank.
    /// # Input
    /// ## bank
    /// The MemoryBank you want to know about.
    /// # Output
    /// A list of values given by each MemoryCell in the DataSet.
    function DataList(bank : MemoryBank) : Bool[][] {
        return Mapped(ValueLookup, bank::DataSet);
    }

    /// # Summary
    /// Given a MemoryBank, it looks up the Value stored at queryAddress.
    /// If the address is not explicitly in the DataSet, the returned value is
    /// 0.
    /// # Input
    /// ## bank
    /// The MemoryBank you want to know about.
    /// ## queryAddress
    /// The address you want to learn the value for.
    /// # Output
    /// The Value as a Bool[] at the queryAddress in the MemoryBank.
    function DataAtAddress(
        bank : MemoryBank,
        queryAddress : Int 
    ) 
    : Bool[] {
        let addressFound = IndexOf(EqualI(_, queryAddress), AddressList(bank));

        if (not EqualI(addressFound, -1)){
            // Look up the actual data value at the correct address index
            return ValueLookup((LookupFunction(bank::DataSet))(addressFound));
        }
        // The address you are looking for may not have been explicitly given,
        // we assume that the data value there is 0.
        else {
            return ConstantArray(bank::DataSize, false);     
        }
    }

    /// # Summary
    /// Takes a DataSet, generates the necessary metadata and wraps it as a 
    /// MemoryBank.
    /// # Input
    /// ## dataSet
    /// The list of MemoryCells that makes up the data for the bank.
    /// # Output
    /// The wrapped MemoryBank.
    function GeneratedMemoryBank(dataSet : MemoryCell[]) : MemoryBank {
        let largestAddress = Max(Mapped(AddressLookup, dataSet));
        mutable valueSize = 0;
        
        // Determine largest size of stored value to set output qubit register size
        for (cell in dataSet){
            if(Length(cell::Value) > valueSize){
                set valueSize = Length(cell::Value);
            }
        }
        return Default<MemoryBank>()
            w/ DataSet <- dataSet
            w/ AddressSize <- BitSizeI(largestAddress)
            w/ DataSize <- valueSize;
    }

    /// # Summary
    /// Transfers the memory register values onto the target register.
    /// # Input
    /// ## memoryRegister
    /// The qubit register that represents the memory you are reading from.
    /// ## auxRegister
    /// Qubit register that will have the same address as addressRegister, but
    /// as a one-hot encoding.
    /// ## targetRegister
    /// The register that will have the memory value transferred to.
    operation ReadoutMemory(
        memoryRegister : MemoryRegister, 
        auxRegister : Qubit[], 
        targetRegister : Qubit[]
    ) 
    : Unit is Adj + Ctl {
        for ((index, auxEnable) in Enumerated(auxRegister)) {
            let range = SequenceI (index * Length(targetRegister), (index + 1) * Length(targetRegister) - 1);
            let memoryPairs = Zip(Subarray(range, memoryRegister!), targetRegister);
            ApplyToEachCA(CCNOT(auxEnable, _, _), memoryPairs);
        }
    }    
}