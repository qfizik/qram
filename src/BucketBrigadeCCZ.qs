﻿namespace Qram{
    
    open Microsoft.Quantum.Math;
    open Microsoft.Quantum.Convert;
    open Microsoft.Quantum.Arrays;
    open Microsoft.Quantum.Canon;
    open Microsoft.Quantum.Intrinsic;
    open Microsoft.Quantum.Arithmetic;
    open Microsoft.Quantum.Measurement;
    open Microsoft.Quantum.Diagnostics;

///////////////////////////////////////////////////////////////////////////
// PUBLIC API
///////////////////////////////////////////////////////////////////////////

    /// # Summary
    /// Creates a QRAM type corresponding to a Bucket Brigade scheme that
    /// heavily parallelizes the T gates by converting Toffolis to CCZs.
    /// # Input
    /// ## dataValues
    /// The data to be stored in the memory.
    /// ## memoryRegister
    /// The register that you want to be initialized with the provided data.
    /// # Output
    /// An instance of the QRAM type that will allow you to use the memory.
    operation BucketBrigadeCCZQRAMOracle(dataValues : MemoryCell[], memoryRegister : MemoryRegister) : QRAM {
        let bank = GeneratedMemoryBank(dataValues);

        for (cell in bank::DataSet) {
            BucketBrigadeWrite(memoryRegister, cell);
        }

        return Default<QRAM>()
            w/ Read <-  BucketBrigadeCCZRead(_, _, _)
            w/ Write <- BucketBrigadeCCZWrite(_, _)
            w/ AddressSize <- bank::AddressSize
            w/ DataSize <- bank::DataSize;
    }

///////////////////////////////////////////////////////////////////////////
// INTERNAL IMPLEMENTATION
///////////////////////////////////////////////////////////////////////////
    
    /// # Summary
    /// Writes a single bit of data to the memory.
    /// # Input
    /// ## memoryRegister
    /// Register that represents the memory you are writing to.
    /// ## dataValue
    /// The tuple of (address, data) that you want written to the memory.
    operation BucketBrigadeCCZWrite(
        memoryRegister : MemoryRegister, 
        dataCell :  MemoryCell
    ) 
    : Unit {
        let (address, data) = (dataCell::Address, dataCell::Value);
        let range = SequenceI (address * Length(data), (address + 1) * Length(data) - 1);
        ResetAll(Subarray(range, memoryRegister!));
        ApplyPauliFromBitString(PauliX, true, data, Subarray(range, memoryRegister!));
    }

    /// # Summary
    /// Reads out a value from a MemoryRegister to a target qubit given an address.
    /// # Input
    /// ## addressRegister
    /// The qubit register that represents the address to be queried.
    /// ## memoryRegister
    /// The qubit register that represents the memory you are reading from.
    /// ## targetRegister
    /// The register that will have the memory value transferred to.
    operation BucketBrigadeCCZRead(
        addressRegister : AddressRegister, 
        memoryRegister : MemoryRegister, 
        targetRegister : Qubit[]
    ) 
    : Unit is Adj + Ctl {
        using (auxRegister = Qubit[2^Length(addressRegister!)]) {
            within {
                X(Head(auxRegister));
                ApplyAddressFanoutCCZ(addressRegister, auxRegister);
            }
            apply {
                ReadoutMemoryCCZ(memoryRegister, auxRegister, targetRegister);
            }
        } 
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
    internal operation ReadoutMemoryCCZ(
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

    /// # Summary
    /// Takes a register with a binary representation of an address and 
    /// converts it to a one-hot encoding in the aux register using T gate parallelization
    /// via CCZs.
    /// # Input
    /// ## addressRegister
    /// Qubit register that uses binary encoding.
    /// ## auxRegister
    /// Qubit register that will have the same address as addressRegister, but
    /// as a one-hot encoding.
    operation ApplyAddressFanoutCCZ(
        addressRegister : AddressRegister, 
        auxRegister : Qubit[]
    ) 
    : Unit is Adj + Ctl {
        for ((idx, addressBit) in Enumerated(addressRegister!)) {
            if (idx == 0) {
                Controlled X([addressRegister![0]],auxRegister[1]);
                Controlled X([auxRegister[1]],auxRegister[0]);
            }
            else {
                // For address bit idx, we are acting on qubits 0 to 2^{idx+1}-1 of the aux register
                // First apply H to the second half
                ApplyToEachCA(H, auxRegister[2^idx..2^(idx+1)-1]);
                // Then apply T to the whole chunk
                ApplyToEachCA(T, auxRegister[0..2^(idx+1)-1]);
                // CNOT cascade from second half to first half
                ApplyToEachCA(CNOT, Zip(auxRegister[2^idx..2^(idx+1)-1], auxRegister[0..2^idx-1]));
                // T dagger to first half
                ApplyToEachCA(Adjoint T, auxRegister[0..2^idx-1]);
                // Now fanout address bit to the full subregister
                ApplyToEachCA(Controlled X([addressRegister![idx]], _), auxRegister[0..2^(idx+1)-1]);
                // T to first half, T dagger to second half
                ApplyToEachCA(T, auxRegister[0..2^idx-1]);
                ApplyToEachCA(Adjoint T, auxRegister[2^idx..2^(idx+1)-1]);
                // Now fanout address bit only to second half
                ApplyToEachCA(Controlled X([addressRegister![idx]], _), auxRegister[2^idx..2^(idx+1)-1]);
                // CNOT cascade from second half to first half
                ApplyToEachCA(CNOT, Zip(auxRegister[2^idx..2^(idx+1)-1], auxRegister[0..2^idx-1]));
                // T dagger to first half                
                ApplyToEachCA(Adjoint T, auxRegister[0..2^idx-1]);
                // Fnout address bit only to first half
                ApplyToEachCA(Controlled X([addressRegister![idx]], _), auxRegister[0..2^idx-1]);
                // Apply H to the second half to undo the first set we did
                ApplyToEachCA(H, auxRegister[2^idx..2^(idx+1)-1]);
                // Finally, apply the last CNOT cascade from second half to first half
                ApplyToEachCA(CNOT, Zip(auxRegister[2^idx..2^(idx+1)-1], auxRegister[0..2^idx-1]));
            }
        }
    }

}